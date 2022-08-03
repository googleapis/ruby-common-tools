# OwlBot postprocessor for Ruby

This is the OwlBot postprocessor for Ruby. It is designed to work with
[OwlBot](https://github.com/googleapis/repo-automation-bots/tree/main/packages/owl-bot)
to regenerate [Ruby GAPIC clients](https://github.com/googleapis/google-cloud-ruby)
by providing the logic to merge newly generated client code with an existing
Ruby library. It is written in Ruby and, unlike postprocessors for some other
languages, does not use synthtool at all.

## Usage

This postprocessor is invoked directly by OwlBot. A library requests use of
this postprocessor by referencing it in the `.OwlBot.yaml` config. A library
can also optionally customize the postprocessor by providing Ruby code.

### Basic usage

To configure a Ruby GAPIC client for OwlBot, create a `.OwlBot.yaml` file in
the library directory. It _must_ instruct OwlBot to copy the newly generated
library code into the directory `/owl-bot-staging/$GEM_NAME` in the repo, and
it _should_ specify the Ruby postprocessor Docker image
`gcr.io/cloud-devrel-public-resources/owlbot-ruby:latest`.

Here is an example OwlBot config:

```yaml
# /google-cloud-access_approval-v1/.OwlBot.yaml

deep-copy-regex:
  - source: /google/cloud/accessapproval/v1/[^/]+-ruby/(.*)
    dest: /owl-bot-staging/google-cloud-access_approval-v1/$1
docker:
  image: gcr.io/cloud-devrel-public-resources/owlbot-ruby:latest
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
* Sync certain metadata files to the current library state, if needed.

Note: This postprocessor is intended to be used with a "staging" strategy for
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
performs the file copying subject to that configuration. You can also perform
other file system operations such as creating, modifying, and deleting files,
both before and after the `OwlBot.move_files` call.

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
need to remove the existing modifiers from the pipeline. The existing default
modifiers are named:

* `preserve_existing_copyright_years`
* `preserve_repo_metadata_release_levels`
* `prevent_overwrite_of_existing_changelog_file`
* `prevent_overwrite_of_existing_gem_version_file`

For example:

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

### Configuring Multi-Wrappers

Ruby has a special type of client, a _multi-wrapper_, that is assembled by the
postprocessor from two or more generator runs. This section describes how to
configure a multi-wrapper.

Ruby _wrapper clients_ are the "main" client used by most customers. A wrapper
is identified with _all_ versions of a single service, and depends on the GAPICs
associated with the various versions of the service, providing factory methods
for client objects and sensible defaults regarding the recommended service
version to use.

Most wrappers are generated by the Ruby generator. A few are handwritten and
include additional higher-level interfaces and client-side logic (i.e. veneers).
Occasionally, however, we want a wrapper that covers a group of two or more
closely related services. One example is the BeyondCorp service, which
architecturally comprises five services (and thus five GAPICs) but should be
presented to users as a single service. This is where a multi-wrapper is useful.

To configure a multi-wrapper, you must provide a special form of the
`.OwlBot.yaml` config file, and a special modifier in the `.owlbot.rb` script.

The `.OwlBot.yaml` config file, rather than copying a generated wrapper directly
into the staging directory for the wrapper, must copy all the generated wrappers
into subdirectories of that staging directory. For example, consider closely
related services `google-cloud-beyond_corp-app_gateways-v1` and
`google-cloud-beyond_corp-client_gateways-v1`, for which we want a single
multi-wrapper `google-cloud-beyond_corp` rather than separate wrappers for
`app_gateways` and `client_gateways`. The OwlBot config would look like this:

```yaml
# /google-cloud-beyond_corp/.OwlBot.yaml

deep-copy-regex:
  - source: /google/cloud/beyondcorp/appgateways/[^/]+-ruby/(.*)
    dest: /owl-bot-staging/google-cloud-beyond_corp/google-cloud-beyond_corp-app_gateways/$1
  - source: /google/cloud/beyondcorp/clientgateways/[^/]+-ruby/(.*)
    dest: /owl-bot-staging/google-cloud-beyond_corp/google-cloud-beyond_corp-client_gateways/$1
docker:
  image: gcr.io/cloud-devrel-public-resources/owlbot-ruby:latest
```

Next, provide an `.owlbot.rb` script that invokes the postprocessor's
multi-wrapper assembly function.

```ruby
# .owlbot.rb

# Assemble a multi-wrapper from these two generated wrappers. This will combine
# files from the subdirectories and generate a multi-wrapper in the main
# staging directory for google-cloud-beyond_corp.
OwlBot.prepare_multi_wrapper(
  [
    "google-cloud-beyond_corp-app_gateways",
    "google-cloud-beyond_corp-client_gateways"
  ],
  pretty_name: "BeyondCorp API"
)

# At this point you can apply any additional modifiers for move_files.

# Perform the file moves
OwlBot.move_files
```

In the list of generated wrappers, the first is special and is used as a source
for some common fields such as product description and URLs. Additionally, if
one of the source generated wrappers has the same name as the desired
multi-wrapper, that source MUST come first. One example of this is
`google-cloud-monitoring` which is the multi-wrapper for
`google-cloud-monitoring`, `google-cloud-monitoring-dashboard`, and
`google-cloud-monitoring-metrics_scope`.

### Automated metadata syncing

One last function of the postprocessor is to sync a few pieces of metadata,
namely the `release_level` in `.repo-metadata.json` and the release version in
snippet metadata files. These fields generally should change during a release
PR, but release-please doesn't know how to do that, so the postprocessor adds
a commit to release PRs with those updates. Currently you cannot customize this
behavior.

## Development

The Ruby postprocessor lives in the GitHub repository
https://github.com/googleapis/ruby-common-tools in the directory
`/owlbot-postprocessor`. Its implementation code is in the `lib` subdirectory,
and tests are provided in the `test` subdirectory.

### Development tools

The `toys` gem is used to run tests and other tasks. Install it using
`gem install toys`.

Under the `/owlbot-postprocessor` directory, the following tools are available:

* `toys build` : Builds a local image of the postprocessor.
* `toys test` : Runs the unit tests. Requires a local postprocessor image.
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
