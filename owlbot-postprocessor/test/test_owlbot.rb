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

describe OwlBot do
  let(:base_dir) { ::File.dirname __dir__ }
  let(:image_name) { "owlbot-postprocessor-test" }
  let(:manifest_file_name) { ".owlbot-manifest.json" }
  let(:gem_name) { "my-gem" }
  let(:repo_dir) { ::File.join __dir__, "tmp" }
  let(:gem_dir) { ::File.join repo_dir, gem_name }
  let(:staging_root_dir) { ::File.join repo_dir, "owl-bot-staging" }
  let(:staging_dir) { ::File.join staging_root_dir, gem_name }
  let(:manifest_path) { ::File.join gem_dir, manifest_file_name }
  let(:manifest) { ::JSON.load_file manifest_path }

  before do
    ::FileUtils.rm_rf repo_dir
    ::FileUtils.mkdir_p repo_dir
    ::Dir.chdir repo_dir do
      `git init`
    end
    ::FileUtils.mkdir_p gem_dir
    ::FileUtils.mkdir_p staging_dir
  end

  after do
    ::FileUtils.rm_rf repo_dir
  end

  def create_staging_file path, content, gem: nil
    dir = gem ? ::File.join(staging_root_dir, gem) : staging_dir
    create_dir_file dir, path, content
  end

  def create_gem_file path, content, gem: nil
    dir = gem ? ::File.join(repo_dir, gem) : gem_dir
    create_dir_file dir, path, content
  end

  def create_dir_file dir, path, content
    path = ::File.join dir, path
    ::FileUtils.mkdir_p ::File.dirname path
    ::File.open path, "w" do |file|
      file.write content
    end
  end

  def create_staging_symlink path, target, gem: nil
    dir = gem ? ::File.join(staging_root_dir, gem) : staging_dir
    create_dir_symlink dir, path, target
  end

  def create_gem_symlink path, target, gem: nil
    dir = gem ? ::File.join(repo_dir, gem) : gem_dir
    create_dir_symlink dir, path, target
  end

  def create_dir_symlink dir, path, target
    path = ::File.join dir, path
    ::FileUtils.mkdir_p ::File.dirname path
    ::File.symlink target, path
  end

  def create_existing_manifest generated: [], static: []
    manifest = {
      "generated" => generated,
      "static" => static
    }
    ::File.open manifest_path, "w" do |file|
      file.write ::JSON.generate manifest
    end
  end

  def assert_gem_file path, content, gem: nil
    dir = gem ? ::File.join(repo_dir, gem) : gem_dir
    path = ::File.join dir, path
    assert ::File.file? path
    assert_equal content, ::File.read(path)
  end

  def refute_gem_file path, gem: nil
    dir = gem ? ::File.join(repo_dir, gem) : gem_dir
    path = ::File.join dir, path
    refute ::File.exist? path
  end

  def assert_gem_symlink path, target, gem: nil
    dir = gem ? ::File.join(repo_dir, gem) : gem_dir
    path = ::File.join dir, path
    assert ::File.symlink?(path), "Not a symlink: #{path}"
    assert_equal target, ::File.readlink(path)
  end

  def invoke_owlbot gem: nil
    ::Dir.chdir repo_dir do
      OwlBot.entrypoint gem_name: gem
    end
  end

  def invoke_owlbot_multi
    ::Dir.chdir repo_dir do
      OwlBot.multi_entrypoint
    end
  end

  it "copies files into an empty gem dir" do
    create_staging_file "hello.txt", "hello world\n"
    create_staging_file "lib/hello.rb", "puts 'hello'\n"

    invoke_owlbot

    assert_gem_file "hello.txt", "hello world\n"
    assert_gem_file "lib/hello.rb", "puts 'hello'\n"
    refute ::File.exist? staging_dir

    paths = ::Dir.glob "**/*", base: gem_dir
    assert_equal 3, paths.size # Two files and one directory

    assert_equal ["hello.txt", "lib/hello.rb"], manifest["generated"]
    assert_equal [], manifest["static"]
  end

  it "copies files into an existing gem dir" do
    create_gem_file "hello.txt", "hello world\n"
    create_gem_file "lib/bye.rb", "puts 'bye'\n"
    create_gem_file "lib/stay.rb", "puts 'stay'\n"
    create_staging_file "hello.txt", "hello again\n"
    create_staging_file "lib/hello.rb", "puts 'hello'\n"
    create_staging_file "lib/stay.rb", "puts 'stay'\n"

    invoke_owlbot

    assert_gem_file "hello.txt", "hello again\n"
    assert_gem_file "lib/bye.rb", "puts 'bye'\n"
    assert_gem_file "lib/hello.rb", "puts 'hello'\n"
    assert_gem_file "lib/stay.rb", "puts 'stay'\n"

    paths = ::Dir.glob "**/*", base: gem_dir
    assert_equal 5, paths.size # Four files and one directory

    assert_equal ["hello.txt", "lib/hello.rb", "lib/stay.rb"], manifest["generated"]
    assert_equal ["lib/bye.rb"], manifest["static"]
  end

  it "deletes files that used to be in the manifest but are no longer generated" do
    create_gem_file "hello.txt", "hello world\n"
    create_gem_file "lib/bye.rb", "puts 'bye'\n"
    create_staging_file "hello.txt", "hello again\n"
    create_staging_file "lib/hello.rb", "puts 'hello'\n"
    create_existing_manifest generated: ["hello.txt", "lib/bye.rb"]

    invoke_owlbot

    assert_gem_file "hello.txt", "hello again\n"
    assert_gem_file "lib/hello.rb", "puts 'hello'\n"
    refute_gem_file "lib/bye.rb"

    paths = ::Dir.glob "**/*", base: gem_dir
    assert_equal 3, paths.size # Two files and one directory

    assert_equal ["hello.txt", "lib/hello.rb"], manifest["generated"]
    assert_equal [], manifest["static"]
  end

  it "preserves changelog and version files when copying" do
    create_gem_file "CHANGELOG.md", "old changelog\n"
    create_gem_file "lib/my/gem/version.rb", "VERSION = 'old'\n"
    create_gem_file "lib/hello.rb", "puts 'hello1'\n"
    create_staging_file "CHANGELOG.md", "new changelog\n"
    create_staging_file "lib/my/gem/version.rb", "VERSION = 'new'\n"
    create_staging_file "lib/hello.rb", "puts 'hello2'\n"

    invoke_owlbot

    assert_gem_file "CHANGELOG.md", "old changelog\n"
    assert_gem_file "lib/my/gem/version.rb", "VERSION = 'old'\n"
    assert_gem_file "lib/hello.rb", "puts 'hello2'\n"

    assert_equal ["CHANGELOG.md", "lib/hello.rb", "lib/my/gem/version.rb"], manifest["generated"]
    assert_equal [], manifest["static"]
  end

  it "handles deletion cases" do
    create_gem_file "CHANGELOG.md", "old changelog\n"
    create_gem_file "lib/my/gem/version.rb", "VERSION = 'old'\n"
    create_gem_file "lib/foo/hello.rb", "puts 'hello1'\n"
    create_gem_file "lib/bar/hello.rb", "puts 'hello2'\n"
    create_existing_manifest generated: ["CHANGELOG.md", "lib/my/gem/version.rb", "lib/foo/hello.rb"]

    invoke_owlbot

    assert_gem_file "CHANGELOG.md", "old changelog\n"
    assert_gem_file "lib/my/gem/version.rb", "VERSION = 'old'\n"
    refute_gem_file "lib/foo/hello.rb"
    refute_gem_file "lib/foo"
    assert_gem_file "lib/bar/hello.rb", "puts 'hello2'\n"

    assert_equal [], manifest["generated"]
    assert_equal ["CHANGELOG.md", "lib/bar/hello.rb", "lib/my/gem/version.rb"], manifest["static"]
  end

  it "preserves copyright year of Ruby files" do
    create_gem_file "lib/hello.rb", "# Copyright 2020 Google LLC\nputs 'hello'"
    create_gem_file "lib/hello.py", "# Copyright 2020 Google LLC\nprint 'hello'"
    create_staging_file "lib/hello.rb", "# Copyright 2021 Google LLC\nputs 'hello again'"
    create_staging_file "lib/hello.py", "# Copyright 2021 Google LLC\nprint 'hello again'"

    invoke_owlbot

    assert_gem_file "lib/hello.rb", "# Copyright 2020 Google LLC\nputs 'hello again'"
    assert_gem_file "lib/hello.py", "# Copyright 2021 Google LLC\nprint 'hello again'"

    assert_equal ["lib/hello.py", "lib/hello.rb"], manifest["generated"]
    assert_equal [], manifest["static"]
  end

  it "deals with types changing" do
    create_gem_file "hello", "hello world\n"
    create_gem_file "foo/bar.rb", "puts 'bar'\n"
    create_staging_file "hello/foo.txt", "hello again\n"
    create_staging_file "foo", "bar\n"

    invoke_owlbot

    assert_gem_file "hello/foo.txt", "hello again\n"
    assert_gem_file "foo", "bar\n"
    refute_gem_file "foo/bar.rb"

    paths = ::Dir.glob "**/*", base: gem_dir
    assert_equal 3, paths.size # Two files and one directory

    assert_equal ["foo", "hello/foo.txt"], manifest["generated"]
    assert_equal [], manifest["static"]
  end

  it "copies, creates, and deletes symlinks" do
    create_gem_symlink "linktodelete", "bye"
    create_gem_symlink "linktokeep", "ruby"
    create_gem_symlink "linktochange", "foo"
    create_staging_symlink "linktoadd", "hello"
    create_staging_symlink "linktochange", "bar"
    create_existing_manifest generated: ["linktochange", "linktodelete"]

    invoke_owlbot

    assert_gem_symlink "linktokeep", "ruby"
    assert_gem_symlink "linktoadd", "hello"
    assert_gem_symlink "linktochange", "bar"
    refute_gem_file "linktodelete"
    assert_equal ["linktoadd", "linktochange"], manifest["generated"]
    assert_equal ["linktokeep"], manifest["static"]
  end

  it "does not list symlink contents in the manifest" do
    create_gem_file "foo/bar.txt", "bar\n"
    create_gem_symlink "link", "foo"
    create_staging_file "hello/world.txt", "hello\n"
    create_staging_symlink "bye", "hello"

    invoke_owlbot

    assert_equal ["bye", "hello/world.txt"], manifest["generated"]
    assert_equal ["foo/bar.txt", "link"], manifest["static"]
  end

  it "honors an owlbot Ruby script" do
    create_gem_file "lib/foo.rb", "puts 'foo'\n"
    create_gem_file "lib/bar.rb", "puts 'bar'\n"
    create_gem_file "lib/baz.rb", "puts 'baz'\n"
    create_gem_file ".owlbot.rb", <<~RUBY
      OwlBot.prevent_overwrite_of_existing "lib/foo.rb"
      OwlBot.modifier path: "lib/bar.rb" do |src|
        src.sub("again", "AGAIN")
      end
      OwlBot.move_files
    RUBY
    create_staging_file "lib/foo.rb", "puts 'foo again'\n"
    create_staging_file "lib/bar.rb", "puts 'bar again'\n"
    create_staging_file "lib/baz.rb", "puts 'baz again'\n"

    invoke_owlbot

    assert_gem_file "lib/foo.rb", "puts 'foo'\n"
    assert_gem_file "lib/bar.rb", "puts 'bar AGAIN'\n"
    assert_gem_file "lib/baz.rb", "puts 'baz again'\n"

    assert_equal ["lib/bar.rb", "lib/baz.rb", "lib/foo.rb"], manifest["generated"]
    assert_equal [".owlbot.rb"], manifest["static"]
  end

  it "updates the manifest" do
    create_gem_file "lib/foo.rb", "puts 'foo'\n"
    create_gem_file "lib/bar.rb", "puts 'bar'\n"
    create_gem_file "lib/baz.rb", "puts 'baz'\n"
    create_gem_file "lib/qux.rb", "puts 'qux'\n"
    create_gem_file ".owlbot.rb", <<~RUBY
      OwlBot.move_files
      FileUtils.rm "\#{OwlBot.gem_dir}/lib/bar.rb"
      FileUtils.rm "\#{OwlBot.gem_dir}/lib/baz.rb"
      File.open "\#{OwlBot.gem_dir}/lib/ruby.rb", "w" do |file|
        file.puts "puts 'ruby'"
      end
      File.open "\#{OwlBot.gem_dir}/ignored.txt", "w" do |file|
        file.puts "whoops"
      end
      OwlBot.update_manifest
    RUBY
    create_gem_file ".gitignore", "ignored.txt\n"
    create_existing_manifest
    create_staging_file "lib/foo.rb", "puts 'foo again'\n"
    create_staging_file "lib/bar.rb", "puts 'bar again'\n"

    invoke_owlbot

    assert_gem_file "lib/foo.rb", "puts 'foo again'\n"
    assert_gem_file "lib/qux.rb", "puts 'qux'\n"
    assert_gem_file "lib/ruby.rb", "puts 'ruby'\n"
    refute_gem_file "lib/bar.rb"
    refute_gem_file "lib/baz.rb"

    assert_equal ["lib/foo.rb"], manifest["generated"]
    assert_equal [".gitignore", ".owlbot.rb", "lib/qux.rb", "lib/ruby.rb"], manifest["static"]
  end

  it "omits gitignored files from the static manifest" do
    create_gem_file "ignored.txt", "ignored\n"
    create_gem_file "static.txt", "static\n"
    create_gem_file "generated.txt", "generated\n"
    create_gem_file ".gitignore", "ignored.txt\n"
    create_staging_file "generated.txt", "generated again\n"

    invoke_owlbot

    assert_gem_file "ignored.txt", "ignored\n"
    create_gem_file "static.txt", "static\n"
    create_gem_file "generated.txt", "generated again\n"
    create_gem_file ".gitignore", "ignored.txt\n"

    assert_equal ["generated.txt"], manifest["generated"]
    assert_equal [".gitignore", "static.txt"], manifest["static"]
  end

  it "supports selecting a specific gem" do
    create_gem_file "hello.txt", "hello world\n"
    create_gem_file "hello.txt", "hello world\n", gem: "another-gem"
    create_staging_file "hello.txt", "hello again\n"
    create_staging_file "hello.txt", "hello again\n", gem: "another-gem"

    invoke_owlbot gem: gem_name

    assert_gem_file "hello.txt", "hello again\n"
    assert_gem_file "hello.txt", "hello world\n", gem: "another-gem"
  end

  it "runs multiple gems" do
    create_gem_file "lib/foo.rb", "puts 'hello'\n", gem: "gem1"
    create_gem_file ".owlbot.rb", <<~RUBY, gem: "gem1"
      OwlBot.modifier path: "lib/foo.rb" do |src|
        src.sub("foo", "bar")
      end
      OwlBot.move_files
    RUBY
    create_gem_file "lib/foo.rb", "puts 'hello'\n", gem: "gem2"
    create_gem_file ".owlbot.rb", <<~RUBY, gem: "gem2"
      OwlBot.modifier path: "lib/foo.rb" do |src|
        src.sub("foo", "baz")
      end
      OwlBot.move_files
    RUBY
    create_staging_file "lib/foo.rb", "puts 'foo'\n", gem: "gem1"
    create_staging_file "lib/foo.rb", "puts 'foo'\n", gem: "gem2"

    invoke_owlbot_multi

    assert_gem_file "lib/foo.rb", "puts 'bar'\n", gem: "gem1"
    assert_gem_file "lib/foo.rb", "puts 'baz'\n", gem: "gem2"
  end

  it "errors if there are multiple staging directories and no explicit gem" do
    create_gem_file "hello.txt", "hello world\n"
    create_gem_file "hello.txt", "hello world\n", gem: "another-gem"
    create_staging_file "hello.txt", "hello again\n"
    create_staging_file "hello.txt", "hello again\n", gem: "another-gem"

    error = assert_raises OwlBot::Error do
      invoke_owlbot
    end
    assert_includes error.message, "there are multiple staging dirs"
  end

  it "errors if there is no staging root dir" do
    ::FileUtils.rm_rf staging_root_dir

    error = assert_raises OwlBot::Error do
      invoke_owlbot
    end
    assert_includes error.message, "No staging root dir"
  end

  it "errors if there are no staging directories under the staging root" do
    ::FileUtils.rm_rf staging_dir

    error = assert_raises OwlBot::Error do
      invoke_owlbot
    end
    assert_includes error.message, "No staging dirs under"
  end

  describe "using the image" do
    def invoke_image *args
      cmd = [
        "docker", "run",
        "--rm",
        "--user", "#{::Process.uid}:#{::Process.gid}",
        "-v", "#{repo_dir}:/repo",
        "-w", "/repo",
        image_name,
        "-qq"
      ] + args
      assert system cmd.join(" ")
    end

    it "copies files using the image" do
      create_gem_file "static.txt", "here before\n"
      create_staging_file "hello.txt", "hello world\n"
      create_staging_file "lib/hello.rb", "puts 'hello'\n"

      invoke_image

      assert_gem_file "hello.txt", "hello world\n"
      assert_gem_file "lib/hello.rb", "puts 'hello'\n"
      assert_gem_file "static.txt", "here before\n"

      paths = ::Dir.glob "**/*", base: gem_dir
      assert_equal 4, paths.size # Three files and one directory

      assert_equal ["hello.txt", "lib/hello.rb"], manifest["generated"]
      assert_equal ["static.txt"], manifest["static"]
    end

    it "supports selecting a specific gem using the image" do
      create_gem_file "hello.txt", "hello world\n"
      create_gem_file "hello.txt", "hello world\n", gem: "another-gem"
      create_staging_file "hello.txt", "hello again\n"
      create_staging_file "hello.txt", "hello again\n", gem: "another-gem"

      invoke_image "--gem=another-gem"

      assert_gem_file "hello.txt", "hello world\n"
      assert_gem_file "hello.txt", "hello again\n", gem: "another-gem"
    end

    it "supports multiple gems" do
      create_gem_file "lib/foo.rb", "puts 'hello'\n", gem: "gem1"
      create_gem_file ".owlbot.rb", <<~RUBY, gem: "gem1"
        OwlBot.modifier path: "lib/foo.rb" do |src|
          src.sub("foo", "bar")
        end
        OwlBot.move_files
      RUBY
      create_gem_file "lib/foo.rb", "puts 'hello'\n", gem: "gem2"
      create_gem_file ".owlbot.rb", <<~RUBY, gem: "gem2"
        OwlBot.modifier path: "lib/foo.rb" do |src|
          src.sub("foo", "baz")
        end
        OwlBot.move_files
      RUBY
      create_staging_file "lib/foo.rb", "puts 'foo'\n", gem: "gem1"
      create_staging_file "lib/foo.rb", "puts 'foo'\n", gem: "gem2"

      invoke_image

      assert_gem_file "lib/foo.rb", "puts 'bar'\n", gem: "gem1"
      assert_gem_file "lib/foo.rb", "puts 'baz'\n", gem: "gem2"
    end

    it "does not fail if there is no staging root dir" do
      ::FileUtils.rm_rf staging_root_dir

      invoke_image
    end
  end
end
