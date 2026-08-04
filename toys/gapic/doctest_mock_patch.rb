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
    if path == "minitest/mock" && defined?(Minitest::Mock) && !Minitest::Mock.instance_methods(false).include?(:orig_expect_for_doctest)
      Minitest::Mock.class_eval do
        alias orig_expect_for_doctest expect
        def expect name, retval, args = [], **kwargs, &blk
          if args.is_a?(Array) && args.last == Hash
            args = args[0...-1]
          end
          kwargs = Hash if kwargs.empty?
          @expected_calls[name] << { retval: retval, args: args, kwargs: kwargs, block: blk }
          self
        end
      end
    end
    res
  end
end
