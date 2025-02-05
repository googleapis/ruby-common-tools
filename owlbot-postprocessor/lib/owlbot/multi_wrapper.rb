# frozen_string_literal: true

# Copyright 2022 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

module OwlBot
  ##
  # OwlBot methods for creating a wrapper that incorporates wrapper factory
  # methods for multiple services
  #
  module MultiWrapper
    ##
    # Convert multiple staged wrappers to a single staged multi-wrapper.
    #
    # The OwlBot copy config must copy the input wrappers into subdirectories
    # of the staging directory. For example, the inputs to the
    # "google-cloud-monitoring" multi-wrapper should be copied into
    # `owl-bot-staging/google-cloud-monitoring/google-cloud-monitoring`,
    # `owl-bot-staging/google-cloud-monitoring/google-cloud-monitoring-dashboard`,
    # `owl-bot-staging/google-cloud-monitoring/google-cloud-monitoring-metrics_scope`.
    #
    # You must then pass an array of the names of the input wrappers, in order.
    # The first element should be the "primary" wrapper that will provide such
    # files as the readme and repo metadata.
    #
    # @param source_gems [Array<String>] An array of the source wrappers.
    #     The first element should be the primary wrapper.
    # @param pretty_name [String] Optional. The pretty name for the final
    #     wrapper.
    #
    def prepare_multi_wrapper source_gems, pretty_name: nil
      if source_gems.include?(gem_name) && source_gems.first != gem_name
        logger.warn "The main gem should be the first entry in the inputs to prepare_multi_wrapper"
        source_gems.delete gem_name
        source_gems.unshift gem_name
      end
      Dir.chdir staging_dir do
        impl = MultiWrapper::Impl.new(*source_gems, pretty_name: pretty_name, final_gem: gem_name)
        impl.prepare
      end
    end

    # @private
    class Impl
      def initialize main_gem, *other_gems, pretty_name:, final_gem:
        @main_gem = main_gem
        @other_gems = other_gems
        @final_gem = final_gem
        @main_pretty_name = read_pretty_name main_gem
        @pretty_name = pretty_name || @main_pretty_name
      end

      def prepare
        copy_all_files @main_gem
        if @main_gem != @final_gem
          adjust_entrypoint
          adjust_repo_metadata
          adjust_rubocop_yml
          adjust_yardopts
          adjust_gemspec
          adjust_authentication_md
          adjust_readme_md
          disable_version @main_gem
          create_synthetic_version
          create_synthetic_main
        end
        unless @other_gems.empty?
          expand_gem_entrypoint
          expand_gemfile
          expand_gemspec_dependencies
          expand_readme_md
        end
        @other_gems.each do |name|
          copy_minimal_files name
          disable_version name
        end
      end

      private

      def read_pretty_name from_gem
        repo_metadata = JSON.parse File.read "#{from_gem}/.repo-metadata.json"
        repo_metadata["name_pretty"]
      end

      def copy_all_files from_gem
        Dir.children(from_gem).each do |item|
          FileUtils.mv "#{from_gem}/#{item}", item
        end
        FileUtils.rm_rf from_gem
      end

      def copy_minimal_files from_gem
        Dir.glob "{lib,test}/*/**/*.rb", base: from_gem do |path|
          FileUtils.mkdir_p File.dirname path
          FileUtils.mv "#{from_gem}/#{path}", path
        end
        FileUtils.rm_rf from_gem
      end

      def disable_version gem_name
        path = "lib/#{make_path gem_name}/version.rb"
        content = File.read path
        content = content.sub(/\n(\s+)VERSION = "\d+\.\d+\.\d+"/, "\n\\1# @private Unused\n\\1VERSION = \"\"")
        File.write path, content
      end

      def adjust_entrypoint
        content = File.read "lib/#{@main_gem}.rb"
        content = content.gsub(/"#{make_path @main_gem}"/, "\"#{make_path}\"")
        content = content.gsub(/#{make_constant @main_gem}::VERSION/, "#{make_constant}::VERSION")
        File.write "lib/#{@final_gem}.rb", content
        File.delete "lib/#{@main_gem}.rb"
      end

      def adjust_repo_metadata
        repo_metadata = JSON.parse File.read ".repo-metadata.json"
        repo_metadata = repo_metadata.to_h do |key, value|
          case key
          when "client_documentation"
            value = value.gsub %r{#{@main_gem}/latest}, "#{@final_gem}/latest"
          when "distribution_name"
            value = @final_gem
          when "name_pretty"
            value = @pretty_name
          end
          [key, value]
        end
        File.write ".repo-metadata.json", JSON.pretty_generate(repo_metadata)
      end

      def adjust_rubocop_yml
        content = File.read ".rubocop.yml"
        content = content.gsub(/"#{@main_gem}.gemspec"/, "\"#{@final_gem}.gemspec\"")
        content = content.gsub %r{"lib/#{@main_gem}.rb"}, "\"lib/#{@final_gem}.rb\""
        File.write ".rubocop.yml", content
      end

      def adjust_yardopts
        content = File.read ".yardopts"
        content = content.gsub(/"#{Regexp.escape @main_pretty_name}"/, "\"#{@pretty_name}\"")
        File.write ".yardopts", content
      end

      def adjust_gemspec
        content = File.read "#{@main_gem}.gemspec"
        content = content.sub %r{"lib/#{make_path @main_gem}/version"}, "\"lib/#{make_path}/version\""
        content = content.gsub(/"#{@main_gem}"/, "\"#{@final_gem}\"")
        content = content.gsub(/#{make_constant @main_gem}::VERSION/, "#{make_constant}::VERSION")
        content = content.sub(/gem\.summary(\s*)= "[^\n]+"\n/,
                              "gem.summary\\1= \"API client library for the #{@pretty_name}\"\n")
        File.write "#{@final_gem}.gemspec", content
        File.delete "#{@main_gem}.gemspec"
      end

      def adjust_authentication_md
        content = File.read "AUTHENTICATION.md"
        content = content.gsub(/([^\w-])#{@main_gem}([^\w-])/, "\\1#{@final_gem}\\2")
        content = content.gsub(/"#{make_path @main_gem}"/, "\"#{make_path}\"")
        File.write "AUTHENTICATION.md", content
      end

      def adjust_readme_md
        content = File.read "README.md"
        content = content.gsub(/([^\w-])#{@main_gem}([^\w-])/, "\\1#{@final_gem}\\2")
        content = content.gsub(/#{Regexp.escape @main_pretty_name}/, @pretty_name)
        File.write "README.md", content
      end

      def create_synthetic_version
        File.open "lib/#{make_path}/version.rb", "w" do |file|
          file.puts file_header
          modules = @final_gem.split("-").map { |str| pascalize str }
          modules.each_with_index do |mod, index|
            indent = "  " * index
            file.puts "#{indent}module #{mod}"
          end
          indent = "  " * modules.size
          file.puts "#{indent}VERSION = \"0.0.1\""
          (modules.size - 1).downto 0 do |index|
            indent = "  " * index
            file.puts "#{indent}end"
          end
        end
      end

      def create_synthetic_main
        File.open "lib/#{make_path}.rb", "w" do |file|
          file.puts file_header
          file.puts "require \"lib/#{@final_gem}\""
        end
      end

      def expand_gem_entrypoint
        File.open "lib/#{@final_gem}.rb", "a" do |file|
          @other_gems.each do |gem_name|
            file.puts "require \"#{make_path gem_name}\" unless defined? #{make_constant gem_name}::VERSION"
          end
        end
      end

      def expand_gemfile
        content = File.read "Gemfile"
        match = /local_dependencies = \[(.*)\]/.match content
        return unless match
        local_deps = match[1].split(/,\s*/)

        @other_gems.each do |gem_name|
          content2 = File.read "#{gem_name}/Gemfile"
          match = /local_dependencies = \[(.*)\]/.match content2
          next unless match
          local_deps += match[1].split(/,\s*/)
        end

        local_deps = local_deps.uniq.join ", "
        content.sub!(/local_dependencies = \[.*\]/, "local_dependencies = [#{local_deps}]")
        File.write "Gemfile", content
      end

      def expand_gemspec_dependencies
        lines = []
        @other_gems.each do |gem_name|
          lines += File.readlines("#{gem_name}/#{gem_name}.gemspec")
                       .select { |line| line.start_with? "  gem.add_dependency \"#{gem_name}" }
        end
        content = File.read "#{@final_gem}.gemspec"
        content = content.sub(/(\n  gem\.add_dependency [^\n]+)\nend/, "\\1\n#{lines.join}end")
        File.write "#{@final_gem}.gemspec", content
      end

      def expand_readme_md
        lines = []
        @other_gems.each do |gem_name|
          File.readlines("#{gem_name}/README.md").each do |line|
            if line =~ %r{^(\[#{gem_name}-v\d\w*\]\(https:[^)]+\))[.,]\n$}
              lines << Regexp.last_match[1]
            end
          end
        end
        lines = lines.join ",\n"
        content = File.read "README.md"
        content = content.sub %r{(\n\[#{@main_gem}-v\d\w*\]\(https:[^)]+\))\.\n}, "\\1,\n#{lines}.\n"
        File.write "README.md", content
      end

      def make_path gem_name = nil
        (gem_name || @final_gem).tr "-", "/"
      end

      def make_constant gem_name = nil
        (gem_name || @final_gem).split("-").map { |str| pascalize str }.join("::")
      end

      def pascalize str
        str.split("_").map(&:capitalize).join
      end

      def file_header
        <<~HEADER
          # frozen_string_literal: true

          # Copyright #{Time.now.year} Google LLC
          #
          # Licensed under the Apache License, Version 2.0 (the "License");
          # you may not use this file except in compliance with the License.
          # You may obtain a copy of the License at
          #
          #     https://www.apache.org/licenses/LICENSE-2.0
          #
          # Unless required by applicable law or agreed to in writing, software
          # distributed under the License is distributed on an "AS IS" BASIS,
          # WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
          # See the License for the specific language governing permissions and
          # limitations under the License.

        HEADER
      end
    end
  end
end
