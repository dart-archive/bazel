# bazel

Bazel support for Dart

**WARNING**: This package is highly experimental.

To use, create a directory structure _similar_ to `workspace`:

```
your_package        (a folder, your _actual_ package, for now)
    lib
    test
    BUILD
BUILD               (empty file is OK)
pubspec.yaml        (like a normal pub package)
WORKSPACE           (see below)
```

You need to `git clone git@github.com:dart-lang/rules_dart.git` repository
somewhere. We will handle this automatically in a future release.

Write to `WORKSPACE`, following this template:

```BUILD
# Dart SDK.
local_repository(
    name = "io_bazel_rules_dart",
    path = "/YOUR/PATH/TO/rules_dart",
)
load(
    "@io_bazel_rules_dart//dart/build_rules:repositories.bzl",
    "dart_repositories",
)
dart_repositories()

# Pubspec converted to Bazel by Bazelify.
load("//:packages.bzl", "bazelify")
bazelify()
```

Then run `bazelify`, which will fill in the `packages.bzl` file referenced
above:

```bash
$ pub global activate --source path path_to_this_package
$ pub global run bazel:bazelify -p path_to_your_workspace
```
