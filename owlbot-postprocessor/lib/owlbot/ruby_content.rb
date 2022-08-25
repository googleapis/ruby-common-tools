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
  # ## RubyContent
  #
  # A tool for identifying simple structural elements of Ruby files to scope
  # find/replace operations. This class lets you do things like "delete this
  # specific method in this specific class", or "replace foo with bar, but only
  # in the documentation for this particular module". It does this by assuming
  # well-formed, indented, and documented Ruby code in compliance with Google
  # Ruby style.
  #
  # To use this tool, instantiate a RubyContent, passing it the contents of a
  # Ruby source file. Then, "select" the piece of code that you want to operate
  # on by walking down the indentation/namespace hierarchy. Once you've narrowed
  # down the scope, you can perform an operation which will be scoped to the
  # selection, and will return the resulting Ruby source file contents.
  #
  # ### Selecting
  #
  # Selection is generally done by identifying blocks and namespaces. For
  # for example, given this input:
  #
  #     ruby_str = <<~CONTENT
  #       # This is a toplevel module
  #       module A
  #         # This is a class
  #         class B
  #           # This is a method
  #           def foo
  #             puts "hello"
  #           end
  #
  #           # This is another method
  #           def bar
  #             puts "hello"
  #           end
  #         end
  #       end
  #     CONTENT
  #
  # You can select the method `A::B#foo` using:
  #
  #     selection = OwlBot::RubyContent.new(ruby_str)
  #       .select_block("module A")
  #       .select_block("class B")
  #       .select_block("def foo")
  #
  # The selection includes both the entire block and its associated
  # documentation contents. So the selection above would include the following
  # part of the source:
  #
  #           # This is a method
  #           def foo
  #             puts "foo"
  #           end
  #
  # When you have a block, you can also select only its documentation, or omit
  # its documentation from the selection.
  #
  # ### Operations
  #
  # Once you have a selection, you can perform an operation scoped to the
  # selection. The most general operation is "modify" which requires you to
  # pass a block that takes the selection as input, and returns modified
  # selection. For example, given the selection of `A::B#foo` above, you can
  # modify it to print "goodbye" instead of "hello" like this:
  #
  #     result = OwlBot::RubyContent.new(ruby_str)
  #       .select_block("module A")
  #       .select_block("class B")
  #       .select_block("def foo")
  #       .modify { |selection| selection.gsub "hello", "goodbye" }
  #
  # The above code returns the entire resulting content, with "goodbye"
  # substituted but only in the "foo" method (not in "bar"). i.e.:
  #
  #     expected_result = <<~CONTENT
  #       # This is a toplevel module
  #       module A
  #         # This is a class
  #         class B
  #           # This is a method
  #           def foo
  #             puts "goodbye"
  #           end
  #
  #           # This is another method
  #           def bar
  #             puts "hello"
  #           end
  #         end
  #       end
  #     CONTENT
  #     assert_equal expected_result, result
  #
  # Because "gsub" is common, there's a convenience method for it:
  #
  #     result = OwlBot::RubyContent.new(ruby_str)
  #       .select_block("module A")
  #       .select_block("class B")
  #       .select_block("def foo")
  #       .gsub "hello", "goodbye"
  #
  # There's also a convenience method for deleting an entire block. It is smart
  # enough to collapse vertical whitespace as well:
  #
  #     result = OwlBot::RubyContent.new(ruby_str)
  #       .select_block("module A")
  #       .select_block("class B")
  #       .select_block("def foo")
  #       .delete
  #     expected_result = <<~CONTENT
  #       # This is a toplevel module
  #       module A
  #         # This is a class
  #         class B
  #           # This is another method
  #           def bar
  #             puts "hello"
  #           end
  #         end
  #       end
  #     CONTENT
  #     assert_equal expected_result, result
  #
  # ### Using in an OwlBot script
  #
  # This class is designed to be used in an OwlBot script, in a modifier block.
  # For example, here's how to delete particular methods cleanly. Note that
  # each time you perform an operation, you "consume" the RubyContent object
  # and if you need to perform another operation you should create a new one
  # from the previous result.
  #
  #     # .owlbot.rb
  #
  #     OwlBot.modifier path: "lib/google/cloud/datastream.rb",
  #                     name: "delete-two-methods" do |content|
  #       # Delete the Google::Cloud::Datastream.locations method
  #       content2 = OwlBot::RubyContent.new(content)
  #         .select_block("module Google")
  #         .select_block("module Cloud")
  #         .select_block("module Datastream")
  #         .select_block("def self.locations")
  #         .delete
  #       # Delete the Google::Cloud::Datastream.iam_policy method
  #       OwlBot::RubyContent.new(content2)
  #         .select_block("module Google")
  #         .select_block("module Cloud")
  #         .select_block("module Datastream")
  #         .select_block("def self.iam_policy")
  #         .delete
  #     end
  #
  #     OwlBot.move_files
  #
  class RubyContent
    ##
    # Create a RubyContent object given Ruby code as a string
    #
    # @param content [String]
    #
    def initialize content, logger: nil, name: nil
      @content = content
      @logger = logger
      @name = name || "Ruby content"
      @range = (0...content.length)
      @outer_indent = @inner_indent = ""
      @complete_block = false
      @hierarchy_description = ["in #{@name}"]
    end

    ##
    # The original content
    # @return [String]
    #
    attr_reader :content
    alias to_s content

    ##
    # The currently selected content, always a substring of {#content}.
    # This should be equal to {#content} when this object is first constructed.
    # If the last selection operation failed to find anything, this will be the
    # empty string.
    #
    # @return [String]
    #
    def selected_content
      @content[@range]
    end

    ##
    # Returns true if the selected content is empty
    # @return [boolean]
    #
    def empty?
      @range.begin == @range.end
    end

    ##
    # Returns the part of the string prior to the selection.
    # This is the empty string when this object is first constructed, since the
    # selection is the entire string.
    #
    # @return [String]
    #
    def pre_content
      @content[0...@range.begin]
    end

    ##
    # Returns the part of the string after the selection.
    # This is the empty string when this object is first constructed, since the
    # selection is the entire string.
    #
    # @return [String]
    #
    def post_content
      @content[@range.end...@content.length]
    end

    ##
    # Selects the given block, if found, within the current selection.
    # The new selection will include documentation comments if any are present.
    # Returns `self` so methods can be chained.
    #
    # @param begin_label [String] The start of the line that signals the
    #     beginning of the block, not including any indentation. For example,
    #     you might pass `"module A"` to select a module block.
    #     You do not need to pass the entire line; it will match if the
    #     beginning of the line matches. For example, if you specify a label of
    #     `"class C"`, it will match `class C < Base`.
    #     If there are multiple matches, it will select the first one.
    # @param end_label [String] The start of the line that signals the end of
    #     the block, not including any indentation. In most cases, you can omit
    #     this and take the default of `"end"` because most blocks end with the
    #     `end` keyword at the current indentation.
    #
    # @return [self]
    #
    def select_block begin_label, end_label = "end"
      begin_label = Regexp.escape begin_label
      end_label = Regexp.escape end_label
      adjust_range "(?:^|\n)" \
                   "((?:#{@inner_indent}#[^\n]*\n+)*" \
                   "#{@inner_indent}#{begin_label}[^\n]*\n+" \
                   "(?:#{@inner_indent}  [^\n]*\n+)*" \
                   "#{@inner_indent}#{end_label}[^\n]*\n)"
      @outer_indent = @inner_indent
      @inner_indent = "  #{@inner_indent}"
      @complete_block = true
      @logger&.warn "Unable to find block #{begin_label.inspect} #{@hierarchy_description.join ' '}" if empty?
      @hierarchy_description.unshift "in block #{begin_label.inspect}"
      self
    end

    ##
    # Selects the documentation comments for the currently selected block, i.e.
    # the documentation at the beginning of the current selection.
    # Returns `self` so methods can be chained.
    #
    # @return [self]
    #
    def select_documentation
      adjust_range "^((?:#{@outer_indent}#[^\n]*\n+)*)", align: :begin
      @inner_indent = @outer_indent
      @complete_block = false
      @logger&.warn "Unable to find any documentation comments #{@hierarchy_description.join ' '}" if empty?
      @hierarchy_description.unshift " in documentation comments"
      self
    end

    ##
    # Removes any documentation comments (i.e. any leading comments) from the
    # current selection.
    # Returns `self` so methods can be chained.
    #
    # @return [self]
    #
    def omit_documentation
      adjust_range "^(?:#{@outer_indent}#[^\n]*\n+)*(.*)$"
      @complete_block = false
      self
    end

    ##
    # Performs a modification to the content, scoped to the current selection,
    # and returns the modified string (leaving the original unchanged).
    #
    # Specify a modification by providing a block. The block takes up to three
    # arguments: the currently selected content as a string, the content before
    # the selection, and the content after the selection. It should either
    # return the modified _selection_ (i.e. not the entire content, but only
    # the selected portion) as a string, or a three-element array of the
    # modified selection, the modified content prior to the selection, and the
    # modified content after the selection.
    #
    # @return [String]
    #
    def modify
      result = yield selected_content, pre_content, post_content
      result = [result, pre_content, post_content] unless result.is_a? Array
      "#{result[1]}#{result[0]}#{result[2]}"
    end

    ##
    # Perform a `gsub` operation on the content, scoped to the current
    # selection, and return the modified string. You can pass any arguments
    # recognized by the Ruby standard `String#gsub` method.
    #
    # @return [String]
    #
    def gsub *args, **kwargs, &block
      modify do |content|
        content.gsub(*args, **kwargs, &block)
      end
    end

    ##
    # Delete the current selection from the content and return the modified
    # content as a string.
    #
    # @return [String]
    #
    def delete
      modify do |_content, before, after|
        if @complete_block
          if before.end_with? "\n\n"
            before = before.chop
          elsif after.start_with? "\n"
            after = after[1..]
          end
        end
        ["", before, after]
      end
    end

    private

    def adjust_range regex_str, align: :end
      match = Regexp.new(regex_str, Regexp::MULTILINE).match @content[@range]
      @range =
        if match
          ((@range.begin + match.begin(1))...(@range.begin + match.end(1)))
        else
          offset = align == :begin ? @range.begin : @range.end
          (offset...offset)
        end
    end
  end
end
