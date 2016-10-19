Bazel support for Dart

**WARNING**: Highly experimental.

To use, create a directory structure _similar_ to `workspace`:

```
your_package        (a folder, your _actual_ package, for now)
                    see https://github.com/dart-lang/rules_dart/issues/13
    lib
    test
    BUILD
pubspec.yaml        (like a normal pub package)
```

## Install

```bash
$ pub global activate --source path path_to_this_package
```

## Run

```bash
your/pkg/dir/ $ pub global run bazel:bazelify
```
