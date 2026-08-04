# frozen_string_literal: true

# Copyright 2026 Google LLC
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

module Kernel
  alias orig_require_for_doctest require
  def require path
    res = orig_require_for_doctest path
    Kernel.patch_minitest_mock_if_needed!
    res
  end

  alias orig_require_relative_for_doctest require_relative
  def require_relative path
    res = orig_require_relative_for_doctest path
    Kernel.patch_minitest_mock_if_needed!
    res
  end

  class << self
    alias orig_singleton_require_for_doctest require
    def require path
      res = orig_singleton_require_for_doctest path
      Kernel.patch_minitest_mock_if_needed!
      res
    end

    def patch_minitest_mock_if_needed!
      return unless defined?(Minitest::Mock)
      return if Minitest::Mock.instance_methods(false).include? :orig_expect_for_doctest
      Minitest::Mock.class_eval do
        alias orig_expect_for_doctest expect
        def expect name, retval, args = [], **kwargs, &blk
          args = args[0...-1] if args.is_a?(Array) && args.last == Hash
          orig_expect_for_doctest name, retval, args, **kwargs, &blk
        end

        alias orig_method_missing_for_doctest method_missing
        def method_missing sym, *args, **kwargs, &block
          orig_method_missing_for_doctest sym, *args, **kwargs, &block
        rescue ArgumentError => e
          raise unless e.message.include? "keyword arguments"
          orig_method_missing_for_doctest sym, *args, &block
        end

        def respond_to_missing? sym, include_private = false
          super
        end
      end
    end
  end
end

Kernel.patch_minitest_mock_if_needed!
