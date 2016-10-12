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
```

Then run `bazelify`:

```bash
$ pub global activate --source path path_to_this_package
$ pub global run bazel:bazelify -p path_to_your_workspace
```
