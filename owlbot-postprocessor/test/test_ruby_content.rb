# frozen_string_literal: true

# Copyright 2021 Google LLC
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

require "helper"
require "fileutils"

describe OwlBot::RubyContent do
  let :input_str do
    <<~CONTENT
      # Copyright blah blah
      #
      # This is license text

      require "ruby"

      ##
      # Module 1
      #
      module Module1
        ##
        # This is a submodule
        #
        module Module1A
          ##
          # This is a class
          #
          class Class1B
            ##
            # Here is a method
            #
            def method1 foo, bar
              puts foo
              puts bar
            end

            def method2 foo
              puts foo
            end
          end

          # Reopen a previous class
          class Class1B
          end

          # Another class
          class Class1E
          end

          ##
          # This is the last class
          #
          class Class1C
          end
        end
      end

      # Module 2

      module Module2
        # This is a class in Module2
        class Class2A
          # Hello
          HELLO = "hello"
        end
      end
    CONTENT
  end

  def assert_start_end start_with, end_with, str
    assert str.start_with?(start_with), "string #{str.inspect} did not start with #{start_with.inspect}"
    assert str.end_with?(end_with), "string #{str.inspect} did not end with #{end_with.inspect}"
  end

  it "starts with the entire file" do
    content = OwlBot::RubyContent.new input_str
    assert_equal input_str, content.content
    refute content.empty?
    assert_equal input_str, content.selected_content
    assert_empty content.pre_content
    assert_empty content.post_content
  end

  it "selects a toplevel module" do
    content = OwlBot::RubyContent.new input_str
    content = content.select_block "module Module1"
    assert_equal input_str, content.content
    refute content.empty?
    assert_start_end "##\n# Module 1\n", "\n  end\nend\n", content.selected_content
    assert_start_end "# Copyright blah blah\n", "require \"ruby\"\n\n", content.pre_content
    assert_start_end "\n# Module 2\n", "\n  end\nend\n", content.post_content
  end

  it "returns empty if a module is not found" do
    content = OwlBot::RubyContent.new input_str
    content = content.select_block "module Module3"
    assert_equal input_str, content.content
    assert content.empty?
    assert_empty content.selected_content
    assert_equal input_str, content.pre_content
    assert_empty content.post_content
  end

  it "selects a submodule" do
    content = OwlBot::RubyContent.new input_str
    content = content.select_block("module Module1")
                     .select_block("module Module1A")
    assert_equal input_str, content.content
    refute content.empty?
    assert_start_end "  ##\n  # This is a submodule\n", "\n    end\n  end\n", content.selected_content
    assert_start_end "# Copyright blah blah\n", "\nmodule Module1\n", content.pre_content
    assert_start_end "end\n", "\n  end\nend\n", content.post_content
  end

  it "selects a buried method" do
    content = OwlBot::RubyContent.new input_str
    content = content.select_block("module Module1")
                     .select_block("module Module1A")
                     .select_block("class Class1B")
                     .select_block("def method2")
    assert_equal input_str, content.content
    refute content.empty?
    assert_equal "      def method2 foo\n        puts foo\n      end\n", content.selected_content
    assert_start_end "# Copyright blah blah\n", "\n        puts bar\n      end\n\n", content.pre_content
    assert_start_end "    end\n", "\n  end\nend\n", content.post_content
  end

  it "selects a block separated from its comment" do
    content = OwlBot::RubyContent.new input_str
    content = content.select_block "module Module2"
    assert_equal input_str, content.content
    refute content.empty?
    assert_start_end "# Module 2\n\nmodule Module2\n", "\n  end\nend\n", content.selected_content
    assert_start_end "# Copyright blah blah\n", "\n  end\nend\n\n", content.pre_content
    assert_empty content.post_content
  end

  it "selects documentation" do
    content = OwlBot::RubyContent.new input_str
    content = content.select_block("module Module1")
                     .select_block("module Module1A")
                     .select_block("class Class1B")
                     .select_block("def method1")
                     .select_documentation
    assert_equal input_str, content.content
    refute content.empty?
    assert_equal "      ##\n      # Here is a method\n      #\n", content.selected_content
    assert_start_end "# Copyright blah blah\n", "\n    class Class1B\n", content.pre_content
    assert_start_end "      def method1 foo, bar\n", "\n  end\nend\n", content.post_content
  end

  it "omits documentation" do
    content = OwlBot::RubyContent.new input_str
    content = content.select_block("module Module1")
                     .select_block("module Module1A")
                     .select_block("class Class1B")
                     .select_block("def method1")
                     .omit_documentation
    assert_equal input_str, content.content
    refute content.empty?
    assert_start_end "      def method1 foo, bar\n", "puts bar\n      end\n", content.selected_content
    assert_start_end "# Copyright blah blah\n", "\n      # Here is a method\n      #\n", content.pre_content
    assert_start_end "\n      def method2 foo\n", "\n  end\nend\n", content.post_content
  end

  it "selects empty documentation" do
    content = OwlBot::RubyContent.new input_str
    content = content.select_block("module Module1")
                     .select_block("module Module1A")
                     .select_block("class Class1B")
                     .select_block("def method2")
                     .select_documentation
    assert_equal input_str, content.content
    assert content.empty?
    assert_empty content.selected_content
    assert_start_end "# Copyright blah blah\n", "\n        puts bar\n      end\n\n", content.pre_content
    assert_start_end "      def method2 foo\n", "\n  end\nend\n", content.post_content
  end

  it "selects unknown class" do
    content = OwlBot::RubyContent.new input_str
    content = content.select_block("module Module1")
                     .select_block("module Module1A")
                     .select_block("class Class1D")
    assert_equal input_str, content.content
    assert content.empty?
    assert_empty content.selected_content
    assert_start_end "# Copyright blah blah\n", "\n    class Class1C\n    end\n  end\n", content.pre_content
    assert_start_end "end\n\n# Module 2\n", "\n  end\nend\n", content.post_content
  end

  it "gsubs content" do
    content = OwlBot::RubyContent.new input_str
    content = content.select_block("module Module1")
                     .select_block("module Module1A")
                     .select_block("class Class1B")
                     .select_block("def method2")
                     .gsub("foo", "foos")
    output_str = content.to_s
    assert_includes output_str, "\n      def method2 foos\n        puts foos\n"
    assert_includes output_str, "\n      def method1 foo, bar\n        puts foo\n"
  end

  it "deletes a lone block" do
    content = OwlBot::RubyContent.new input_str
    content = content.select_block("module Module2")
                     .select_block("class Class2A")
                     .delete
    output_str = content.to_s
    assert_includes output_str, "\nmodule Module2\nend\n"
  end

  it "deletes the first block" do
    content = OwlBot::RubyContent.new input_str
    content = content.select_block("module Module1")
                     .select_block("module Module1A")
                     .select_block("class Class1B")
                     .delete
    output_str = content.to_s
    assert_includes output_str, "\n  module Module1A\n    # Reopen a previous class\n"
  end

  it "deletes the last block" do
    content = OwlBot::RubyContent.new input_str
    content = content.select_block("module Module1")
                     .select_block("module Module1A")
                     .select_block("class Class1C")
                     .delete
    output_str = content.to_s
    assert_includes output_str, "\n    class Class1E\n    end\n  end\n"
  end

  it "deletes a middle block" do
    content = OwlBot::RubyContent.new input_str
    content = content.select_block("module Module1")
                     .select_block("module Module1A")
                     .select_block("class Class1E")
                     .delete
    output_str = content.to_s
    assert_includes output_str, "\n    class Class1B\n    end\n\n    ##\n    # This is the last class\n"
  end

  it "deletes documentation" do
    content = OwlBot::RubyContent.new input_str
    content = content.select_block("module Module1")
                     .select_block("module Module1A")
                     .select_block("class Class1C")
                     .select_documentation
                     .delete
    output_str = content.to_s
    assert_includes output_str, "\n    class Class1E\n    end\n\n    class Class1C\n"
  end
end
