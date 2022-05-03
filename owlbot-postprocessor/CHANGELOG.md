# Changelog

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
