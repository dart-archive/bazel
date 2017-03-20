## 0.3.5

* Update to rules_dart 0.4.3

## 0.3.4

* Add support for using a local Dart SDK
* Bump to latest `_bazel_codegen`
* Upgrade to rules_dart 0.4.2

## 0.3.3

* Add support for doing codegen in external packages
* Upgrade rules_dart 0.4.1

## 0.3.2

* Add suggestions for .gitignore
* Allow empty `target` in `build.yaml`
* Upgrade to latest rules_dart - previous versions were broken
* More specific error message when `build\` exists
* Limited codegen support

## 0.3.1

* Bug fix: Bump the dependency on _bazel_codegen since 0.0.1 is broken

## 0.3.0

### Package rename

* Previously this package was released as `bazel`. It's now called `dazel`

### New features
* Add `dazel build` command, which can build a web app and create a deployable
  directory for it (using dart2js), similar to `pub build`.
    * Has a single positional argument which should be the path to the html file
      for the app to build. For example, `dazel build web/index.html`.
    * Has a single optional argument `--output-dir` which defaults to `deploy`.
      The abbreviation `o` is supported for this argument as well.

## 0.2.2

* Update to rules dart 0.2.2 with the latest dev sdk

## 0.2.0

* Refactor of rules_dart with a smaller public surface area of skylark rules
* Doc improvements
* More friendly error handling
* Added check for analyzer ignores
* Improved discovery of web targets

## 0.1.1

* Moved default `bazel` command to subcommand `bazel init`
* Added `bazel serve` command.
* Updated `rules_dart` to `0.1.1`.
* Generally improved CLI behavior with incorrect flags.
