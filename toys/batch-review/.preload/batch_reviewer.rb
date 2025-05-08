# frozen_string_literal: true

# Copyright 2024 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


module Yoshi
  ##
  # Implementation of a batch review tool.
  #
  class BatchReviewer
    def self.well_known_presets
      @well_known_presets ||= begin
        releases_preset = Preset.new do |preset|
          preset.desc = "Selects all release pull requests, and expect diffs appropriate to a release pull request"
          preset.pull_request_filter.only_titles(/^chore\(main\): release [\w-]+ \d+\.\d+\.\d+/)
          preset.pull_request_filter.only_users(["release-please[bot]"])
          preset.diff_expectations.expect name: "release-please-manifest" do |expect|
            expect.change_type(:changed).path_pattern(/\.release-please-manifest\.json$/)
          end
          preset.diff_expectations.expect name: "changelog" do |expect|
            expect.change_type(:changed).path_pattern(/\/CHANGELOG\.md$/)
          end
          preset.diff_expectations.expect name: "version" do |expect|
            expect.change_type(:changed).path_pattern(/\/version\.rb$/)
          end
        end
        {
          basic_releases: releases_preset
        }
      end
    end

    def initialize repo
      @repo = repo
      @presets = {}
    end

    def define_preset name, based_on: nil
      if based_on
        preset = @presets[based_on] || BatchReviewer.well_known_presets[based_on]
        raise "Unknown based_on #{based_on.inspect}" unless preset
        preset = preset.clone
      else
        preset = Preset.new
      end
      @presets[name.to_s] = preset
      yield preset if block_given?
    end

    def preset_names
      @presets.keys
    end

    def lookup_preset name
      @presets[name]
    end

    def config preset_name: nil,
               preset: nil,
               only_titles: nil,
               omit_titles: nil,
               only_users: nil,
               omit_users: nil,
               only_labels: nil,
               omit_labels: nil,
               only_ids: nil,
               omit_ids: nil,
               message: nil,
               edit_message: false,
               automerge: false,
               assert_diffs_clean: false,
               merge_delay: nil,
               max_diff_size: nil,
               editor: nil,
               dry_run: false
      preset ||= @presets[preset_name] || Preset.new
      @pull_request_filter = preset.pull_request_filter
      @pull_request_filter.only_titles only_titles
      @pull_request_filter.omit_titles omit_titles
      @pull_request_filter.only_users only_users
      @pull_request_filter.omit_users omit_users
      @pull_request_filter.only_labels only_labels
      @pull_request_filter.omit_labels omit_labels
      @pull_request_filter.only_ids Array(only_ids).map{ |spec| parse_ids spec }
      @pull_request_filter.omit_ids Array(omit_ids).map{ |spec| parse_ids spec }
      @diff_expectations = preset.diff_expectations
      @automerge = automerge
      @assert_diffs_clean = assert_diffs_clean
      @merge_delay = merge_delay
      @max_diff_size = max_diff_size
      @message = parse_message message, preset, automerge
      @edit_message = edit_message
      @editor = editor || ENV["EDITOR"] || "/bin/nano"
      @dry_run = dry_run
      raise "Automerge must be off to support editing commit messages" if @edit_message && @automerge
    end

    def run context
      @context = context
      @next_timestamp = Process.clock_gettime Process::CLOCK_MONOTONIC
      @merged_count = 0
      @skipped_count = 0
      check_runtime_environment
      @pull_requests = PullRequest.find context: @context,
                                        repo: @repo,
                                        pull_request_filter: @pull_request_filter,
                                        diff_expectations: @diff_expectations
      @context.logger.info "Found #{@pull_requests.size} pull requests"
      check_assert_diffs_clean if @assert_diffs_clean
      @merge_delay ||= default_merge_delay @pull_requests.size
      @pull_requests.each_with_index { |pr, index| handle_pr pr, index + 1 }
      @context.puts
      @context.puts "Totals: #{@merged_count} merged and #{@skipped_count} skipped out of #{@pull_requests.size}", :bold
    end

    private

    def parse_message message, preset, automerge
      message = preset.message if message.nil? || message.empty?
      if message.nil? || message.empty?
        if automerge
          raise "--message is required if --automerge is specified"
        else
          message = [:pr_title]
        end
      end
      Array(message).map do |line|
        case line
        when :pr_title, ":pr_title"
          :pr_title
        when :pr_title_number, ":pr_title_number"
          :pr_title_number
        when Symbol, /^:/
          raise "Unknown message code: #{line}"
        else
          line.to_s
        end
      end
    end

    def default_merge_delay count
      delay = count / 2
      delay = 15 if delay > 15
      @context.logger.info "Defaulting merge delay to #{delay} seconds"
      delay
    end

    def parse_ids expr
      case expr
      when /^(\d+)$/
        num = Regexp.last_match[1].to_i
        num..num
      when /^(\d+)-(\d+)$/
        num1 = Regexp.last_match[1].to_i
        num2 = Regexp.last_match[2].to_i
        num1..num2
      when Range
        expr
      when Integer
        expr..expr
      else
        raise "Unknown IDs format: #{expr.inspect}"
      end
    end

    def check_runtime_environment
      unless @context.exec(["gh", "--version"]).success?
        raise "Could not find the GitHub CLI. See https://cli.github.com/manual/ for install instructions."
      end
      return if @automerge
      unless @context.exec(["ydiff", "--version"]).success?
        raise "Could not find the ydiff command. See https://github.com/ymattw/ydiff/ for install instructions."
      end
    end

    def check_assert_diffs_clean
      failure = false
      @pull_requests.each do |pr|
        next if pr.fully_expected?
        pr.diff_files.each do |file|
          next if file.matching_expectation
          @context.puts "PR##{pr.id}: File #{file.path} does not match expectations.", :red, :bold
        end
        failure = true
      end
      @context.exit 1 if failure
    end

    def handle_pr pr, index
      if @automerge
        if pr.fully_expected?
          resolve_message pr do |message|
            do_merge pr, index, message
          end
          @merged_count += 1
        else
          @context.puts "Skipping PR##{pr.id} #{pr.title.inspect} (#{index}/#{@pull_requests.size})", :bold, :yellow
          @skipped_count += 1
        end
      else
        display_pr pr, index
        confirm_pr pr, index do |message|
          do_merge pr, index, message
        end
      end
    end

    def resolve_message pr
      message = @message.map do |line|
        case line
        when :pr_title
          pr.title.dup
        when :pr_title_number
          "#{pr.title} (##{pr.id})"
        else
          line.dup
        end
      end
      yield message.join "\n"
    end

    def display_pr pr, index
      @context.puts
      @context.puts "PR##{pr.id} #{pr.title.inspect} (#{index}/#{@pull_requests.size})", :cyan, :bold
      diff_text = []
      pr.diff_files.each do |file|
        if file.matching_expectation
          @context.puts "Diff expected: #{file.path} (#{file.matching_expectation.desc})"
        else
          diff_text << file.text
        end
      end
      if diff_text.empty?
        @context.puts "All diffs expected for this pull request!", :green
      elsif pr.unexpected_diff_line_count > @max_diff_size
        @context.puts "Too many unexpected diffs to display (#{pr.unexpected_diff_line_count} lines)", :yellow
      else
        @context.puts "Unexpected diffs:", :yellow
        @context.puts "--------", :yellow, :bold
        run_ydiff diff_text
        @context.puts "--------", :yellow, :bold
      end
    end

    def run_ydiff diff_text
      require "toys/utils/pager"
      command = ["ydiff", "--width=0", "-s", "--wrap"]
      Toys::Utils::Pager.start(command: command) { |io| io.puts diff_text }
    end

    def confirm_pr pr, index
      resolve_message pr do |message|
        @context.puts "Message: #{message.inspect}" unless @edit_message
        if @context.confirm "Merge? ", default: true
          message = run_editor message if @edit_message
          yield message
          @merged_count += 1
        else
          @context.puts "Skipped: PR##{pr.id} #{pr.title.inspect} (#{index}/#{@pull_requests.size})", :bold, :yellow
          @skipped_count += 1
        end
      end
    end

    def run_editor message
      require "tempfile"
      file = Tempfile.new "commit-message"
      begin
        file.write "#{message.strip}\n\n# Edit the commit message here.\n# Lines beginning with a hash are stripped.\n"
        file.rewind
        @context.exec [@editor, file.path]
        file.read.gsub(/^#[^\n]*\n?/, "").strip
      ensure
        file.close
        file.unlink
      end
    end

    def do_merge pr, index, message
      message = pr.custom_message message
      if @dry_run
        @context.puts "Dry run: PR##{pr.id} #{pr.title.inspect} (#{index}/#{@pull_requests.size})", :bold, :green
        return
      end
      cur_time = Process.clock_gettime Process::CLOCK_MONOTONIC
      if cur_time < @next_timestamp
        @context.logger.info "Delaying #{@next_timestamp - cur_time}s before next merge..."
        sleep(@next_timestamp - cur_time)
      end
      @context.logger.info "Approving PR #{pr.id}..."
      retry_gh ["repos/#{@repo}/pulls/#{pr.id}/reviews",
                "--field", "event=APPROVE",
                "--field", "body=Approved using batch-review"],
               name: "gh pull request approval"
      @context.logger.info "Merging PR #{pr.id}..."
      passing_errors = [{
        "status" => "405",
        "message" => "Merge already in progress"
      }]
      title, detail = message.split "\n", 2
      retry_gh ["-XPUT", "repos/#{@repo}/pulls/#{pr.id}/merge",
                "--field", "merge_method=squash",
                "--field", "commit_title=#{title}",
                "--field", "commit_message=#{detail}"],
               name: "gh pull request merge",
               passing_errors: passing_errors
      @context.puts "Merged PR##{pr.id} #{pr.title.inspect} (#{index}/#{@pull_requests.size})", :bold, :green
      @next_timestamp = Process.clock_gettime(Process::CLOCK_MONOTONIC) + @merge_delay
    end

    def retry_gh args, tries: 3, name: nil, passing_errors: nil
      cmd = ["gh", "api"] + args
      name ||= cmd.inspect
      passing_errors = Array passing_errors
      result = nil
      tries.times do |num|
        result = @context.exec cmd, out: :capture, err: :capture
        return if result.success?
        break unless result.error?
        @context.puts result.captured_out unless result.captured_out.empty?
        @context.puts result.captured_err unless result.captured_err.empty?
        message = JSON.parse result.captured_out rescue {}
        if passing_errors.any? { |spec| spec.all? { |k, v| message[k] == v } }
          @context.puts "Interpreting error as passing when calling #{name}", :yellow
          return
        end
        @context.logger.info "waiting to retry..."
        sleep 2 * (num + 1)
      end
      @context.puts "Repeatedly failed to call #{name}", :red, :bold
      @context.exit 1
    end

    class Preset
      def initialize
        @pull_request_filter = PullRequestFilter.new
        @diff_expectations = DiffExpectationSet.new
        @message = []
        @desc = "(no description provided)"
        yield self if block_given?
      end

      def clone
        copy = Preset.new
        copy.pull_request_filter = @pull_request_filter.clone
        copy.diff_expectations = @diff_expectations.clone
        copy.message = @message.dup
        copy.desc = @desc.dup
        copy
      end

      attr_accessor :pull_request_filter
      attr_accessor :diff_expectations
      attr_accessor :message
      attr_accessor :desc
    end

    class PullRequestFilter
      def initialize
        clear_only_titles!
        clear_omit_titles!
        clear_only_users!
        clear_omit_users!
        clear_only_labels!
        clear_omit_labels!
        clear_only_ids!
        clear_omit_ids!
        omit_labels "do not merge"
        yield self if block_given?
      end

      def only_titles titles
        @only_titles += Array(titles)
        self
      end

      def omit_titles titles
        @omit_titles += Array(titles)
        self
      end

      def only_users users
        @only_users += Array(users)
        self
      end

      def omit_users users
        @omit_users += Array(users)
        self
      end

      def only_labels labels
        @only_labels += Array(labels)
        self
      end

      def omit_labels labels
        @omit_labels += Array(labels)
        self
      end

      def only_ids ids
        @only_ids += Array(ids)
        self
      end

      def omit_ids ids
        @omit_ids += Array(ids)
        self
      end

      def clear_only_titles!
        @only_titles = []
        self
      end

      def clear_omit_titles!
        @omit_titles = []
        self
      end

      def clear_only_users!
        @only_users = []
        self
      end

      def clear_omit_users!
        @omit_users = []
        self
      end

      def clear_only_labels!
        @only_labels = []
        self
      end

      def clear_omit_labels!
        @omit_labels = []
        self
      end

      def clear_only_ids!
        @only_ids = []
        self
      end

      def clear_omit_ids!
        @omit_ids = []
        self
      end

      def clone
        copy = PullRequestFilter.new
        copy.clear_omit_labels!
        copy.only_titles @only_titles
        copy.omit_titles @omit_titles
        copy.only_users @only_users
        copy.omit_users @omit_users
        copy.only_labels @only_labels
        copy.omit_labels @omit_labels
        copy.only_ids @only_ids
        copy.omit_ids @omit_ids
        copy
      end

      def match? pr
        return false if !@only_ids.empty? && !@only_ids.any? { |range| range === pr.id }
        return false if !@omit_ids.empty? && @omit_ids.any? { |range| range === pr.id }
        return false if !@only_titles.empty? && !@only_titles.any? { |pattern| pattern === pr.title }
        return false if !@omit_titles.empty? && @omit_titles.any? { |pattern| pattern === pr.title }
        return false if !@only_users.empty? && !@only_users.any? { |pattern| pattern === pr.user }
        return false if !@omit_users.empty? && @omit_users.any? { |pattern| pattern === pr.user }
        return false if !@only_labels.empty? && !@only_labels.intersect?(pr.labels)
        return false if !@omit_labels.empty? && @omit_labels.intersect?(pr.labels)
        true
      end
    end

    class DiffExpectation
      def initialize
        clear!
      end

      def clear!
        @desc = nil
        @path_patterns = []
        @change_type = :any
        @allowed_additions = []
        @allowed_deletions = []
        @required_additions = []
        @required_deletions = []
        @denied_additions = []
        @denied_deletions = []
      end

      def change_type val = nil
        if val.nil?
          @change_type
        else
          @change_type = val.to_sym
          self
        end
      end

      def desc val = nil
        if val.nil?
          @desc || begin
            list = []
            list << (path_patterns.empty? ? "Any file" : "Files matching #{path_patterns.inspect}")
            case change_type
            when :created
              list << "newly created"
            when :deleted
              list << "being deleted"
            when :changed
              list << "being changed"
            when :indented
              list << "containing only indentation changes"
            end
            list << "completely matching allowed regexes" if !allowed_additions.empty? || !allowed_deletions.empty?
            list << "with further content requirements" if !required_additions.empty? || !required_deletions.empty? ||
                                                           !denied_additions.empty? || !denied_deletions.empty?
            list.join ", "
          end
        else
          @desc = val
          self
        end
      end

      attr_reader :path_patterns
      attr_reader :allowed_additions
      attr_reader :allowed_deletions
      attr_reader :required_additions
      attr_reader :required_deletions
      attr_reader :denied_additions
      attr_reader :denied_deletions

      def path_pattern regex
        @path_patterns << regex
        self
      end

      def allowed_addition regex
        @allowed_additions << regex
        self
      end

      def allowed_deletion regex
        @allowed_deletions << regex
        self
      end

      def required_addition regex
        @required_additions << regex
        self
      end

      def required_deletion regex
        @required_deletions << regex
        self
      end

      def denied_addition regex
        @denied_additions << regex
        self
      end

      def denied_deletion regex
        @denied_deletions << regex
        self
      end

      def match? file
        return false if !path_patterns.empty? && !path_patterns.any? { |pat| pat === file.path }
        case change_type
        when :created
          return false if file.type != "N"
        when :deleted
          return false if file.type != "D"
        when :changed
          return false if file.type != "C"
        when :indented
          return false unless file.only_indentation
        end
        check_allowed = !allowed_additions.empty? || !allowed_deletions.empty?
        check_additional = !required_additions.empty? || !required_deletions.empty? ||
                           !denied_additions.empty? || !denied_deletions.empty?
        return true unless check_allowed || check_additional
        remaining_required_additions = required_additions.dup
        remaining_required_deletions = required_deletions.dup
        file.each_hunk do |hunk|
          hunk.each do |line|
            line_without_mark = line[1..]
            if line.start_with? "+"
              return false if denied_additions.any? { |regex| regex.match? line_without_mark }
              return false if check_allowed && !allowed_additions.any? { |regex| regex.match? line_without_mark }
              remaining_required_additions.delete_if { |regex| regex.match? line_without_mark }
            elsif line.start_with? "-"
              return false if denied_deletions.any? { |regex| regex.match? line_without_mark }
              return false if check_allowed && !allowed_deletions.any? { |regex| regex.match? line_without_mark }
              remaining_required_deletions.delete_if { |regex| regex.match? line_without_mark }
            end
          end
        end
        remaining_required_additions.empty? && remaining_required_deletions.empty?
      end
    end

    class DiffExpectationSet
      def initialize
        @named = {}
        @anonymous = []
        yield self if block_given?
      end

      def clone
        DiffExpectationSet.new do |copy|
          @named.each do |name, expectation|
            copy.expect expectation, name: name
          end
          @anonymous.each do |expectation|
            copy.expect expectation
          end
        end
      end

      def empty?
        @named.empty? && @anonymous.empty?
      end

      def get name
        @named[name]
      end

      def clear! name
        @named.delete name
        self
      end

      def matching_expectation diff_file
        (@named.values + @anonymous).find { |expectation| expectation.match? diff_file }
      end

      def expect expectation = nil, name: nil
        expectation ||= DiffExpectation.new
        yield expectation if block_given?
        if name
          raise "Name #{name} already exists" if @named.key? name
          @named[name] = expectation
        else
          @anonymous << expectation
        end
        self
      end
    end

    class PullRequest
      def self.find context:,
                    repo:,
                    pull_request_filter:,
                    diff_expectations:
        require "json"
        results = []
        page = 1
        loop do
          path = "repos/#{repo}/pulls?per_page=80&page=#{page}"
          results_page = JSON.parse context.capture(["gh", "api", path], e: true)
          break if results_page.empty?
          results_page.each do |pr_resource|
            pr = PullRequest.new context, repo, pr_resource, diff_expectations
            next unless pull_request_filter.match? pr
            results << pr
          end
          page += 1
        end
        results
      end

      def initialize context, repo, pr_resource, diff_expectations
        @resource = pr_resource
        @context = context
        @repo = repo
        @diff_expectations = diff_expectations
      end

      attr_reader :resource

      def id
        @id ||= resource["number"].to_i
      end

      def title
        @title ||= resource["title"]
      end

      def user
        @user ||= resource["user"]["login"]
      end

      def labels
        @labels ||= Array(resource["labels"]).map { |label| label["name"] }
      end

      def raw_diff_data
        @raw_diff_data ||= begin
          cmd = ["curl", "-s", "-f", "https://patch-diff.githubusercontent.com/raw/#{@repo}/pull/#{id}.diff"]
          @context.capture cmd, e: true
        end
      end

      def diff_files
        @diff_files ||= begin
          "\n#{raw_diff_data.chomp}"
            .split("\ndiff --git ")
            .slice(1..-1)
            .map { |text| DiffFile.new "diff --git #{text}\n", @diff_expectations }
        end
      end

      def fully_expected?
        diff_files.all? { |file| file.matching_expectation }
      end

      def unexpected_diff_line_count
        @unexpected_diff_line_count ||=
          diff_files.reduce 0 do |count, file|
            if file.matching_expectation
              count
            else
              count + file.hunk_lines_count
            end
          end
      end

      def lib_name
        unless defined? @lib_name
          @lib_name =
            case title
            when /^\[CHANGE ME\] Re-generated google-cloud-(?<basename>[\w-]+) to pick up changes in the API or client/
              Regexp.last_match[:basename]
            when /^\[CHANGE ME\] Re-generated (?<fullname>[\w-]+) to pick up changes in the API or client/
              Regexp.last_match[:fullname]
            else
              interpret_lib_name
            end
        end
        @lib_name
      end

      def custom_message message
        return message unless lib_name
        message.gsub(/^(feat|docs|fix)(!?):\s+(\S.*)$/, "\\1(#{lib_name})\\2: \\3")
      end

      private

      def interpret_lib_name
        name = nil
        diff_files.each do |diff_file|
          return nil unless %r{^([^/]+)/} =~ diff_file.path
          possible_name = Regexp.last_match[1]
          if name.nil?
            name = possible_name
          elsif name != possible_name
            return nil
          end
        end
        name
      end
    end

    class DiffFile
      def initialize text, diff_expectations
        @text = text
        @lines = text.split "\n"
        @path =
          if @lines.first =~ %r{^diff --git a/(\S+) b/\S+$}
            Regexp.last_match[1]
          else
            ""
          end
        @type =
          case @lines[1].to_s
          when /^new file/
            "N"
          when /^deleted file/
            "D"
          else
            "C"
          end
        initial_analysis
        @matching_expectation = diff_expectations.matching_expectation self
      end

      attr_reader :text
      attr_reader :path
      attr_reader :type
      attr_reader :only_indentation
      attr_reader :added_lines_count
      attr_reader :deleted_lines_count
      attr_reader :hunk_lines_count
      attr_reader :matching_expectation

      def each_hunk
        hunk = nil
        @lines.each do |line|
          if line.start_with? "@@"
            yield hunk if hunk && !hunk.empty?
            hunk = []
          elsif hunk
            hunk << line
          end
        end
        yield hunk if hunk && !hunk.empty?
      end

      private

      def initial_analysis
        @only_indentation = true
        @common_directory = nil
        @added_lines_count = 0
        @deleted_lines_count = 0
        @hunk_lines_count = 0
        each_hunk do |hunk|
          analyze_only_indentation hunk
          analyze_counts hunk
        end
      end

      def analyze_only_indentation hunk
        return unless @only_indentation
        minuses = [""]
        pos = 1
        @only_indentation = false
        catch :fail do
          hunk.each do |line|
            if line.start_with? "-"
              if pos == minuses.length
                minuses = [line]
                pos = 0
              elsif pos.zero?
                minuses << line
              else
                throw :fail
              end
            elsif line.start_with? "+"
              throw :fail unless pos < minuses.length && minuses[pos].sub(/^-\s*/, "") == line.sub(/^\+\s*/, "")
              pos += 1
            elsif line.start_with? " "
              throw :fail unless pos == minuses.length
            else
              throw :fail
            end
          end
          @only_indentation = true
        end
      end

      def analyze_counts hunk
        hunk.each do |line|
          @hunk_lines_count += 1
          if line.start_with? "-"
            @deleted_lines_count += 1
          elsif line.start_with? "+"
            @added_lines_count += 1
          end
        end
      end
    end

    class Template
      include Toys::Template

      def initialize batch_reviewer
        @batch_reviewer = batch_reviewer
      end

      attr_reader :batch_reviewer

      on_expand do |template|
        cur_preset = Preset.new
        cur_expectation = nil
        config_started = false

        desc "Mass code review tool"

        long_desc \
          "batch-reviewer is a mass code review tool. It can be used to " \
            "analyze, approve, and merge large numbers of pull requests " \
            "with similar properties or diffs.",
          "",
          "In a nutshell, batch-reviewer:",
          "* Selects a set of pull requests based on criteria that can " \
            "include title, user, and labels.",
          "* Analyzes the diffs in the selected pull requests and compares " \
            "then to a set of configurable expected diffs.",
          "* Either autoapproves and automerges pull requests whose diffs " \
            "conform to expectations, or interactively displays unexpected " \
            "diffs and prompts whether to merge or skip.",
          "",
          "In many cases, you can use a preset configuration by passing its " \
            "name as an argument. Presets generally set a particular filter " \
            "on the selected pull requests and a particular set of expected " \
            "diffs for those pulls. See the description of CONFIG for a list " \
            "of supported preset names. Otherwise you can configure the pull " \
            "request selectors and diff expectations explicitly by passing " \
            "flags.",
          "",
          "To automerge pull requests with expected diffs, pass --automerge. " \
            "This mode will skip any pull requests with unexpected diffs. " \
            "If --automerge is not passed, merges are done interactively; " \
            "any unexpected diffs are displayed, and the tool prompts for " \
            "confirmation on each merge."

        flag :preset, "--config NAME", accept: template.batch_reviewer.preset_names do
          desc "The name of an optional preset configuration"
          long_desc \
            "The name of an optional preset configuration, representing a " \
              "starting point for the review setup. It includes pull request " \
              "selectors, expected diffs, and commit message settings. You " \
              "can pass additional flags to further modify the configuration.",
            "Supported values are:", ""
          template.batch_reviewer.preset_names.each do |name|
            long_desc "* #{name}: #{template.batch_reviewer.lookup_preset(name).desc}"
          end
          handler do |config|
            # TODO: Return a UsageError instead of raising, once Toys supports it
            raise "Cannot set a config after a config or expectation has already been set" if config_started
            config_started = true
            cur_preset = template.batch_reviewer.lookup_preset config
          end
        end

        flag_group desc: "Pull request selectors" do
          long_desc \
            "These flags filter the set of pull requests that will be " \
              "considered by this tool."
          flag :only_title_re, accept: Regexp, handler: :push, default: [],
               desc: "a regex that matches pull request titles to select"
          flag :only_title, accept: String, handler: :push, default: [],
               desc: "an exact pull request title to select"
          flag :omit_title_re, accept: Regexp, handler: :push, default: [],
               desc: "a regex that matches pull request titles to omit"
          flag :omit_title, accept: String, handler: :push, default: [],
               desc: "an exact pull request title to omit"
          flag :only_user, accept: String, handler: :push, default: [],
               desc: "pull request opener username to select"
          flag :omit_user, accept: String, handler: :push, default: [],
               desc: "pull request opener username to omit"
          flag :only_label, accept: String, handler: :push, default: [],
               desc: "pull request label to select"
          flag :omit_label, accept: String, handler: :push, default: [],
               desc: "pull request label to omit"
          flag :only_ids, accept: String, handler: :push, default: [] do
            desc "pull request ID or range of IDs to select"
            long_desc \
              "Pull request ID or range of IDs to select.",
              "This flag may be provided multiple times. Each value can be " \
              "either an integer or a range (inclusive of endpoints) " \
              "separated by a hyphen."
          end
          flag :omit_ids, accept: String, handler: :push, default: [] do
            desc "pull request ID or range of IDs to omit"
            long_desc \
              "Pull request ID or range of IDs to omit.",
              "This flag may be provided multiple times. Each value can be " \
              "either an integer or a range (inclusive of endpoints) " \
              "separated by a hyphen."
          end
        end

        flag_group desc: "Commit messages" do
          flag :message, accept: String, handler: :push, default: [] do
            desc "custom commit messager"
            long_desc \
              "Specify the commit message to use. This flag can be provided " \
                "multiple times to specify a multi-line message. The " \
                "--message must be specified explicitly if --automerge is " \
                "in effect, otherwise it defaults to `:pr_title`.",
              "The value can be either a static commit message, or one of " \
                "the following special values (omitting the backticks):",
              "* `:pr_title` - use the pull request title",
              "* `:pr_title_number` - use the pull request title and number"
          end
          flag :edit_message,
               desc: "edit the commit message in an editor for each merge"
          flag :editor, accept: String,
               desc: "path to the editor program to use for editing commit message details"
        end

        flag_group desc: "Execution options" do
          flag :automerge,
               desc: "automatically merge pull requests whose diffs satisfy expectations"
          flag :assert_diffs_clean,
               desc: "assert that all selected pull request diffs satisfy expectations"
          flag :merge_delay, accept: Integer,
               desc: "delay in seconds between subsequent merges"
          flag :max_diff_size, accept: Integer, default: 500,
               desc: "maximum size in lines for displaying unexpected diffs"
          flag :dry_run,
               desc: "execute in dry run mode, which does not approve or merge pull requests"
        end

        flag_group desc: "Expectations" do
          long_desc \
            "Expectations are descriptions of file diffs. If a file in a " \
              "pull request's diff matches an expectation, the file is " \
              "omitted from display in the batch reviewer. This helps remove " \
              "clutter so reviews can focus on the interesting diffs.",
            "",
            "You can set up zero or more expectations. Each has an optional " \
              "name and description, and each will contain criteria that can " \
              "match file paths, types of change (e.g. file created or " \
              "modified), and actual diffs (lines added and removed). Any " \
              "pull request file that matches at least one expectation is " \
              "omitted from display. You can also configure batch review " \
              "to automerge any pull requests whose file diffs ALL match " \
              "expectation.",
            "",
            "To configure an expectation, start with the `--expect` flag. " \
              "Then subsequently provide other flags in this group to " \
              "specify how that expectation is configured. To configure more " \
              "than one expectation, use `--expect` again to finish " \
              "configuring the current expectation and start a new one. You " \
              "can also optionally give an expectation a name; this will let " \
              "you \"re-open\" the expectation later to modify its " \
              "configuration. This is often used to modify expectations " \
              "configured in a preset configuration."
          flag :expect, "--expect[=NAME]" do
            desc "start configuring a diff expectation"
            handler do |name|
              name = nil unless name.is_a? String
              config_started = true
              cur_expectation = cur_preset.diff_expectations.get name
              unless cur_expectation
                cur_expectation = DiffExpectation.new
                cur_preset.diff_expectations.expect cur_expectation, name: name
              end
              cur_expectation
            end
          end
          flag :desc, "--desc=DESC" do
            desc "set a description for the current expectation"
            handler do |desc|
              # TODO: Return a UsageError instead of raising, once Toys supports it
              raise "need to start an expectation with --expect before using --desc" unless cur_expectation
              cur_expectation.desc desc
            end
          end
          flag :clear do
            desc "clear the current expectation"
            handler do
              # TODO: Return a UsageError instead of raising, once Toys supports it
              raise "need to start an expectation with --expect before using --clear" unless cur_expectation
              cur_expectation.clear!
            end
          end
          flag :created do
            desc "configure the current expectation to expect newly created files"
            handler do
              # TODO: Return a UsageError instead of raising, once Toys supports it
              raise "need to start an expectation with --expect before using --created" unless cur_expectation
              cur_expectation.change_type :created
            end
          end
          flag :deleted do
            desc "configure the current expectation to expect deleted files"
            handler do
              # TODO: Return a UsageError instead of raising, once Toys supports it
              raise "need to start an expectation with --expect before using --deleted" unless cur_expectation
              cur_expectation.change_type :deleted
            end
          end
          flag :changed do
            desc "configure the current expectation to expect modified files"
            handler do
              # TODO: Return a UsageError instead of raising, once Toys supports it
              raise "need to start an expectation with --expect before using --changed" unless cur_expectation
              cur_expectation.change_type :changed
            end
          end
          flag :indented do
            desc "configure the current expectation to expect reindented files"
            handler do
              # TODO: Return a UsageError instead of raising, once Toys supports it
              raise "need to start an expectation with --expect before using --indented" unless cur_expectation
              cur_expectation.change_type :indented
            end
          end
          flag :path, "--path=REGEX" do
            desc "expect a file path matching the given regex"
            handler do |regex|
              # TODO: Return a UsageError instead of raising, once Toys supports it
              raise "need to start an expectation with --expect before using --path" unless cur_expectation
              cur_expectation.path_pattern Regexp.new regex
            end
          end
          flag :allow_add, "--allow-add=REGEX", "--add=REGEX" do
            desc "expect an added content line matching the given regex"
            handler do |regex|
              # TODO: Return a UsageError instead of raising, once Toys supports it
              raise "need to start an expectation with --expect before using --allow-add" unless cur_expectation
              cur_expectation.allowed_addition Regexp.new regex
            end
          end
          flag :allow_del, "--allow-del=REGEX", "--del=REGEX" do
            desc "expect a deleted content line matching the given regex"
            handler do |regex|
              # TODO: Return a UsageError instead of raising, once Toys supports it
              raise "need to start an expectation with --expect before using --allow-del" unless cur_expectation
              cur_expectation.allowed_deletion Regexp.new regex
            end
          end
          flag :require_add, "--require-add=REGEX" do
            desc "require an added content line matching the given regex"
            handler do |regex|
              # TODO: Return a UsageError instead of raising, once Toys supports it
              raise "need to start an expectation with --expect before using --require-add" unless cur_expectation
              cur_expectation.required_addition Regexp.new regex
            end
          end
          flag :require_del, "--require-del=REGEX" do
            desc "require a deleted content line matching the given regex"
            handler do |regex|
              # TODO: Return a UsageError instead of raising, once Toys supports it
              raise "need to start an expectation with --expect before using --require-del" unless cur_expectation
              cur_expectation.required_deletion Regexp.new regex
            end
          end
          flag :deny_add, "--deny-add=REGEX" do
            desc "disallow an added content line matching the given regex"
            handler do |regex|
              # TODO: Return a UsageError instead of raising, once Toys supports it
              raise "need to start an expectation with --expect before using --deny-add" unless cur_expectation
              cur_expectation.denied_addition Regexp.new regex
            end
          end
          flag :denydel, "--deny-del=REGEX" do
            desc "disallow a deleted content line matching the given regex"
            handler do |regex|
              # TODO: Return a UsageError instead of raising, once Toys supports it
              raise "need to start an expectation with --expect before using --deny-del" unless cur_expectation
              cur_expectation.denied_deletion Regexp.new regex
            end
          end
        end

        static :batch_reviewer, template.batch_reviewer

        include :exec
        include :terminal

        def run
          batch_reviewer.config preset: preset,
                                only_titles: only_title_re + only_title,
                                omit_titles: omit_title_re + omit_title,
                                only_users: only_user,
                                omit_users: omit_user,
                                only_labels: only_label,
                                omit_labels: omit_label,
                                only_ids: only_ids,
                                omit_ids: omit_ids,
                                message: message,
                                edit_message: edit_message,
                                automerge: automerge,
                                assert_diffs_clean: assert_diffs_clean,
                                merge_delay: merge_delay,
                                max_diff_size: max_diff_size,
                                editor: editor,
                                dry_run: dry_run
          batch_reviewer.run self
        end
      end
    end
  end
end
