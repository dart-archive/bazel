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

To setup a workspace, follow this template:

```BUILD
# Dart SDK.
local_repository(
    name = "io_bazel_rules_dart",
    path = "/your/path/to/rules_dart",
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

You'll need to `git clone` the `rules_dart` directory, and hook it up
where you see `/your/path/to/rules_dart` above. We will handle this
automatically in a future release.
