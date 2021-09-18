# OwlBot postprocessor for Ruby

This is the OwlBot postprocessor for Ruby. It is designed to work with
[OwlBot](https://github.com/googleapis/repo-automation-bots/tree/main/packages/owl-bot)
to regenerate [Ruby GAPIC clients](https://github.com/googleapis/google-cloud-ruby)
by providing the logic to merge newly generated client code with an existing
Ruby library.

## Usage

This postprocessor is invoked directly by OwlBot. A library requests use of
this postprocessor by referencing it in the `.OwlBot.yaml` config. A library
can also optionally customize the postprocessor by providing Ruby code.

### Basic usage

To configure a Ruby GAPIC client for OwlBot, create a `.OwlBot.yaml` file in
the library directory. It _must_ instruct OwlBot to copy the newly generated
library code into the directory `/owl-bot-staging/$GEM_NAME` in the repo. It
also _should_ specify the Ruby postprocessor Docker image
`gcr.io/cloud-devrel-public-resources/owlbot-ruby:latest` (unless a global
`/.github/.OwlBot.yaml` file already does so).

Here is an example OwlBot config:

```yaml
# /google-cloud-access_approval-v1/.OwlBot.yaml

docker:
  image: gcr.io/cloud-devrel-public-resources/owlbot-ruby:latest
deep-copy-regex:
  - source: /google/cloud/accessapproval/v1/google-cloud-accessapproval-v1-ruby/(.*)
    dest: /owl-bot-staging/google-cloud-access_approval-v1/$1
```

This postprocessor will then, by default:

* Copy generated files from the staging directory into the gem directory.
* Preserve any existing `version.rb` (assuming it is in the expected location)
  and `CHANGELOG.md` files.
* Preserve existing copyright years in Ruby source files.
* Delete any files that were _previously generated_ but are no longer
  generated. (Does not touch files that were added by hand.)
* Create a file called `.owlbot-manifest.json` in the library directory that
  tracks the list of generated files for the previous step.

Note: This preprocessor is intended to be used with a "staging" strategy for
OwlBot. That is, OwlBot itself copies newly generated files into a staging
directory, and the postprocessor is responsible for moving the files from there
into the final location. As a result, the `deep-remove-regex` and
`deep-preserve-regex` OwlBot configuration keys are probably not useful.

### Customizing the behavior

A library can customize the behavior of this postprocessor by providing a file
in the library directory called `.owlbot.rb`. If present, this file is executed
by the postprocessor and _must_ perform all the needed functionality, including
copying files from the staging directory, and making any desired changes.

For this purpose, the `.owlbot.rb` file will have access to the `OwlBot` module
which provides useful methods for implementing postprocessing functionality.
In general, usage of this module involves first configuring a pipeline of
_modifiers_ which affect how generated files are handled as they are moved from
the staging directory, and then finally calling `OwlBot.move_files` which
performs the file copying subject to that configuration.

Following is an example `.owlbot.rb` file:

```ruby
# .owlbot.rb

# Install a modifier that renames a particular class in all Ruby files
OwlBot.modifier path: %r{^lib/.*\.rb$} do |content|
  content.gsub "BadlyNamedClass", "BetterName"
end

# Omit a particular generated file by removing it from the staging directory
FileUtils.rm_f File.join(OwlBot.staging_dir, "unnecessary.txt")

# Perform the file moves
OwlBot.move_files
```

By default, the `OwlBot` module is preconfigured with the default postprocessor
behavior: preservation of `version.rb` and `CHANGELOG.md` and preservation of
copyright years. Thus, the following `.owlbot.rb` file would have an identical
effect to not having an `.owlbot.rb` file at all:

```ruby
# "default" .owlbot.rb

# Just perform the file moves with the default configuration
OwlBot.move_files
```

As a result, if you want to override/disable the default behavior, you will
need to remove the existing modifiers from the pipeline. For example:

```ruby
# .owlbot.rb

# The changelog is named differently in this library, so remove the default
# modifier and install a different one.
OwlBot.remove_modifiers_named "prevent_overwrite_of_existing_changelog_file"
OwlBot.prevent_overwrite_of_existing "HISTORY.md"

OwlBot.move_files
```

For detailed reference documentation on the `OwlBot` module, see the file
`lib/owlbot.rb`.

## Development

The Ruby preprocessor lives in the GitHub repository
https://github.com/googleapis/ruby-common-tools in the directory
`/owlbot-preprocessor`. Its implementation code is in the `lib` subdirectory,
and tests are provided in the `test` subdirectory.

### Development tools

The `toys` gem is used to run tests and other tasks. Install it using
`gem install toys`.

Under the `/owlbot-preprocessor` directory, the following tools are available:

* `toys build` : Builds a local image of the preprocessor.
* `toys test` : Runs the unit tests. Requires a local preprocessor image.
* `toys rubocop` : Runs rubocop lint and style checks.
* `toys ci` : Runs both test and rubocop.

Some commands have flags that can be passed in. Pass the `--help` flag to any
command for more details.

### Releases

Releases are handled via release-please. After a release-please pull request is
merged, a GitHub Actions job will automatically tag the release. This will, in
turn, trigger a Cloud Build job that builds the production image (with the
`latest` Docker image tag.)

Normally, release-please will offer a release PR automatically after semantic
changes are merged into the owlbot-postprocessor directory. It can also be run
manually by triggering the "Release-Please OwlBot Postprocessor" GitHub Action.
When triggering manually, you can also specify a particular version.

It is also possible to build "ad-hoc" test images using the `toys release dev`
command. These images are tagged with a timestamp (rather than `latest`). You
need sufficient permissions in the "cloud-devrel-public-resources" project to
run an ad-hoc build.
