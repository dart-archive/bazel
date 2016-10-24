[Bazel][bazel] extension support for [Dart][dart].

Bazel is a _correct, reproducible, and fast_ build tool used internally at
Google, and now open source, that provides a powerful and extensible framework
for building software and maintaining code.

[bazel]: https://www.bazel.io/
[dart]: https://www.dartlang.org/

## Why Bazel

Large applications in Google like [AdWords Next][blog-awn] and
[AdSense][blog-ads] have used Dart and [Angular Dart][angular-dart] in
production with Bazel for a while, and now we want to share Bazel with the rest
of the community.

[blog-awn]: http://news.dartlang.org/2016/03/the-new-adwords-ui-uses-dart-we-asked.html
[blog-ads]: http://news.dartlang.org/2016/10/google-adsense-angular-dart.html
[angular-dart]: https://angular.io/dart


## Getting Started

[file-issue]: https://github.com/dart-lang/bazel/issues/new

> **WARNING**: This package is highly experimental. While the underlying
> framework (such as BUILD rules and extensions) are stable, we're still
> iterating on a good stable solution for end users that are used to primarily
> working with pub and `pubspec.yaml` files.
>
> Have a suggestion to make this better? [File an issue][file-issue].

Our Bazel package publishes a `bazelify` command that takes an existing pub
package and automatically generates a Bazel worskpace: full of extensions,
macros, rules, and more.

### Installation

[install-bazel]: https://www.bazel.io/versions/master/docs/install.html

> **NOTE**: bazelify requires an existing installation of [bazel][install-bazel]


If you're familiar with [`pub run`][pub_run], then `bazelify` is easy:

[pub_run]: https://www.dartlang.org/tools/pub/cmd/pub-run

```bash
$ pub global activate bazel
```

### Generation

You can run `bazelify` on a typical `pub` package:

```
my_new_package/
  bin/
  lib/
  web/
  pubspec.yaml
```

```bash
$ cd my_new_package
$ pub global run bazel:bazelify
```

If you don't have a project, you can use our `workspace` folder of examples.
See `tool/presubmit.dart` for some examples.

### Usage

You can `bazel run` files in `bin/`:

```bash
# Assume you have bin/hello.dart
# We automatically generate a "hello_bin" target in your BUILD file.
$ bazel run :hello_bin
```

You can also `bazel run` a development sever for your web application:

```bash
# Assume you have web/main.dart, and web/index.html.
$ bazel run :main_dartium_serve
```

Oh, and did we mention support for the [Dart dev compiler][DDC]?

[ddc]: https://github.com/dart-lang/dev_compiler

```bash
$ bazel run :main_ddc_serve
```

### Cleaning up

We automatically generate a bunch of file for you - don't worry about checking
them in for now - you can safely ignore them when commiting. Here is an example
snippet you can include in a `.gitignore`:

```gitignore
/bazel-*
.bazelify
packages.bzl
BUILD
WORKSPACE
```

You may also want to exclude the `bazel-*` folders from the Dart analyzer
using an `.analysis_options` file. This prevents the Dart analyzer from
accidentally "seeing" generated and copied code and needlessly analyzing it.

```
analyzer:
  exclude:
    - 'bazel-*/**'
```
