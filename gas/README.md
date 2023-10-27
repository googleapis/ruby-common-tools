# Gas: Gems As a Service

This is a tool that handles several different concerns around the release of
Ruby Gem packages. Specifically, it can:

* Build and test binary gems from source gems
* Publish gems to rubygems.org

It is designed to be executed as part of a release pipeline. Currently (as of
Feb 2023) it is to be used as part of the
[google-protobuf](https://github.com/protocolbuffers/protobuf) release
pipeline for Ruby. The client release pipeline will build a source gem (as well
as gem platforms such as Java that are not built using extconf), and pass those
artifacts as inputs into Gas. Gas will then build the binary gem archives, and
publish _all_ the gems including the input source gem and the generated binary
gems, to rubygems.org.

Gas is implemented as a set of command line scripts using
[toys](https://github.com/dazuma/toys). It will be hosted on GCP VMs using the
internal CI/CD system Kokoro.

For more information, see internal document go/ruby-gas-design.

This is not an official Google product.
