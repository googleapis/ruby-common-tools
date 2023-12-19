# Common toys imports

The subdirectories under this directory provide common toys tools and libraries
used across multiple Google Cloud SDK Ruby language repositories.

Specifically:

* `/toys/gapic` provides a common set of tools used by GAPIC libraries,
  including builds, various test types, and CI.
* `/toys/release` provides the Ruby release system, including tools for
  controlling release-please, performing Rubygems releases, and building and
  publishing reference documentation.
* `/toys/yoshi` provides a set of utility classes for performing common steps
  such as interacting with GitHub and opening pull requests.

These resources can be invoked using the `load_git` directive. For example,
GAPIC libraries can bring in `toys/gapic` using

```ruby
load_git remote: "https://github.com/googleapis/ruby-common-tools.git",
         path: "toys/gapic",
```
