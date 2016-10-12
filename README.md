# bazel

Bazel support for Dart

**WARNING**: This package is highly experimental.

To use, create a directory structure _similar_ to `workspace`:

```
your_package        (a folder, your _actual_ package, for now)
                    see https://github.com/dart-lang/rules_dart/issues/13
    lib
    test
    BUILD
pubspec.yaml        (like a normal pub package)
WORKSPACE           (see below)
```
 
Write to `WORKSPACE`, following this template (we will handle this
automatically in a future release):

```BUILD
# Dart SDK.
git_repository(
    name = "io_bazel_rules_dart",
    remote = "https://github.com/dart-lang/rules_dart",
    tag = "0.0.0-alpha",
)
load("@io_bazel_rules_dart//dart/build_rules:repositories.bzl", "dart_repositories")
dart_repositories()

# Pubspec converted to Bazel by Bazelify.
load("//:packages.bzl", "bazelify")
bazelify()
```

Then run `bazelify`, which will fill in the `packages.bzl` referenced above:

```bash
$ pub global activate --source path path_to_this_package
$ pub global run bazel:bazelify -p path_to_your_workspace
```
