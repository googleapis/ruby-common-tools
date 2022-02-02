# Changelog

## [0.4.0](https://www.github.com/googleapis/ruby-common-tools/compare/owlbot-postprocessor/v0.3.0...owlbot-postprocessor/v0.4.0) (2022-02-02)


### Features

* **owlbot:** Preserve release_level repo metadata field ([#67](https://www.github.com/googleapis/ruby-common-tools/issues/67)) ([e71a809](https://www.github.com/googleapis/ruby-common-tools/commit/e71a80949ba5a1cd94291d17d9a896c490f973d5))

## [0.3.0](https://www.github.com/googleapis/ruby-common-tools/compare/owlbot-postprocessor/v0.2.4...owlbot-postprocessor/v0.3.0) (2021-09-28)

* Provide a call to update the manifest after post-move changes ([9f7a5c3](https://www.github.com/googleapis/ruby-common-tools/commit/9f7a5c30e40de891dda369511124d8236e3d0a9c))
* Handle symlinks correctly in the owlbot postprocessor ([bbe0e97](https://www.github.com/googleapis/ruby-common-tools/commit/bbe0e97a23b42d4562de1c622fa35c7edeb01b68))

## [0.2.4](https://www.github.com/googleapis/ruby-common-tools/compare/owlbot-postprocessor/v0.2.3...owlbot-postprocessor/v0.2.4) (2021-09-20)

* Don't fail the postprocessor docker image if there's nothing to do ([cc927d0](https://www.github.com/googleapis/ruby-common-tools/commit/cc927d0287a8fcb307c461b7c8f434f91cafbffa))

## [0.2.3](https://www.github.com/googleapis/ruby-common-tools/compare/owlbot-postprocessor/v0.2.2...owlbot-postprocessor/v0.2.3) (2021-09-20)

* Improve error messages for unexpected staging directory structure ([2b50ee8](https://www.github.com/googleapis/ruby-common-tools/commit/2b50ee8861d29e3a4ed04e1bb6a54a68c5b667bf))
* Support owlbot runs that modify multiple gems ([1817085](https://www.github.com/googleapis/ruby-common-tools/commit/181708544f7e676b6e0bc1e7785c378a879a7cde))

## [0.2.2](https://www.github.com/googleapis/ruby-common-tools/compare/owlbot-postprocessor/v0.2.1...owlbot-postprocessor/v0.2.2) (2021-09-18)

* Ensure manifest files end with a newline ([96cfa79](https://www.github.com/googleapis/ruby-common-tools/commit/96cfa7983c17f32bfdfddf23344bed5b44f1bd9c))

## [0.2.1](https://www.github.com/googleapis/ruby-common-tools/compare/owlbot-postprocessor/v0.2.0...owlbot-postprocessor/v0.2.1) (2021-09-18)

* Exclude the owlbot manifest file itself from its static file list ([4566430](https://www.github.com/googleapis/ruby-common-tools/commit/456643013b4025adb569edf63f69249fca9eaa10))

## [0.2.0](https://www.github.com/googleapis/ruby-common-tools/compare/owlbot-postprocessor/v0.1.4...owlbot-postprocessor/v0.2.0) (2021-09-18)

* BREAKING CHANGE: Removed preserved paths and reimplemented changelog/version preservation using modifiers. Changelog/version files no longer switch from generated to static in the manifest. ([e79233c](https://www.github.com/googleapis/ruby-common-tools/commit/e79233cdd086e270a6a4068aea2755b558eea4d0))
* Omit gitignored files from the owlbot static manifest ([700e88b](https://www.github.com/googleapis/ruby-common-tools/commit/700e88bd4828022246a548e4e712d93567f89991))
* Support arguments passed to the postprocessor. Support selecting a gem using the `--gem=NAME` option. ([492377c](https://www.github.com/googleapis/ruby-common-tools/commit/492377c9a877658538ed8c8026ceb77175754a0a))

## [0.1.4](https://www.github.com/googleapis/ruby-common-tools/compare/owlbot-postprocessor/v0.1.3...owlbot-postprocessor/v0.1.4) (2021-09-17)

* Fixes to readme ([f084f28](https://www.github.com/googleapis/ruby-common-tools/commit/f084f2847c578f430ccfa09090ef67ebfee14e13))

## [0.1.3](https://www.github.com/googleapis/ruby-common-tools/compare/owlbot-postprocessor/v0.1.2...owlbot-postprocessor/v0.1.3) (2021-09-17)

* Release tooling for owlbot-postprocessor ([8af1476](https://www.github.com/googleapis/ruby-common-tools/commit/8af147686e04eacaccb462dbcf36b0b80ad3151f))
