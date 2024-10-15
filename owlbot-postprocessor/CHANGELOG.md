# Changelog

### 0.9.10 (2024-10-15)

#### Bug Fixes

* Update Ruby to 3.3.5 ([#342](https://github.com/googleapis/ruby-common-tools/issues/342)) 

### 0.9.9 (2024-07-26)

#### Bug Fixes

* update Ruby and other packages ([#338](https://github.com/googleapis/ruby-common-tools/issues/338)) 

### 0.9.8 (2024-06-11)

#### Bug Fixes

* Another postprocessor fix for multi-wrapper ([#330](https://github.com/googleapis/ruby-common-tools/issues/330)) 

### 0.9.7 (2024-06-11)

#### Bug Fixes

* Fix multi-wrapper dependencies that were broken when dropping Ruby 2.7 ([#328](https://github.com/googleapis/ruby-common-tools/issues/328)) 

### 0.9.6 (2024-04-05)

#### Bug Fixes

* temporary change in postprocessor to require ostruct for test helpers ([#317](https://github.com/googleapis/ruby-common-tools/issues/317)) 

### 0.9.5 (2024-02-24)

#### Bug Fixes

* Second try to fix multiwrapper ([#312](https://github.com/googleapis/ruby-common-tools/issues/312)) 

### 0.9.4 (2024-02-24)

#### Bug Fixes

* Fix multiwrapper construction to account for Gemfile changes for Ruby 2.7 ([#310](https://github.com/googleapis/ruby-common-tools/issues/310)) 
* Run on Ruby 3.2 ([#297](https://github.com/googleapis/ruby-common-tools/issues/297)) 

### 0.9.3 (2024-01-04)

#### Bug Fixes

* Updates to Ruby and Toys ([#288](https://github.com/googleapis/ruby-common-tools/issues/288)) 

### 0.9.2 (2023-03-20)

#### Bug Fixes

* Remove ruby-doc.org link hack ([#193](https://github.com/googleapis/ruby-common-tools/issues/193)) 

### 0.9.1 (2022-12-05)

#### Bug Fixes

* Fixed ruby-doc.org links using the old pre-2022 format ([#140](https://github.com/googleapis/ruby-common-tools/issues/140)) 

### 0.9.0 (2022-10-18)

#### Features

* Analyze the library and set library_type in repo-metadata ([#133](https://github.com/googleapis/ruby-common-tools/issues/133)) 

### 0.8.0 (2022-08-03)

#### Features

* Tools for creating multi-wrappers ([#104](https://github.com/googleapis/ruby-common-tools/issues/104)) 

### 0.7.1 (2022-07-25)

#### Bug Fixes

* Change default release level from unknown to unreleased ([#101](https://github.com/googleapis/ruby-common-tools/issues/101)) 

### 0.7.0 (2022-05-17)

#### Features

* Provide a Ruby content tool

### 0.6.1 (2022-05-03)

#### Bug Fixes

* Set up writable directories for bundler installs and toys cache

### 0.6.0 (2022-05-03)

#### Features

* Support toys in the owlbot postprocessor

### 0.5.2 (2022-04-28)

#### Bug Fixes

* Set snippet metadata client version to blank pre-0.1

### 0.5.1 (2022-04-27)

#### Bug Fixes

* Preserve working directory if an owlbot script changes it

### 0.5.0 (2022-04-27)

#### Features

* Preserve version field in snippet metadata files
* Update repo metadata and snippet metadata for release PRs

### 0.4.0 (2022-02-02)

* Preserve release_level repo metadata field

### 0.3.0 (2021-09-28)

* Provide a call to update the manifest after post-move changes
* Handle symlinks correctly in the owlbot postprocessor

### 0.2.4 (2021-09-20)

* Don't fail the postprocessor docker image if there's nothing to do

### 0.2.3 (2021-09-20)

* Improve error messages for unexpected staging directory structure
* Support owlbot runs that modify multiple gems

### 0.2.2 (2021-09-18)

* Ensure manifest files end with a newline

### 0.2.1 (2021-09-18)

* Exclude the owlbot manifest file itself from its static file list

### 0.2.0 (2021-09-18)

* BREAKING CHANGE: Removed preserved paths and reimplemented changelog/version preservation using modifiers. Changelog/version files no longer switch from generated to static in the manifest.
* Omit gitignored files from the owlbot static manifest
* Support arguments passed to the postprocessor. Support selecting a gem using the `--gem=NAME` option.

### 0.1.4 (2021-09-17)

* Fixes to readme

### 0.1.3 (2021-09-17)

* Release tooling for owlbot-postprocessor
