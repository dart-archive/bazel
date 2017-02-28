`dazel` is a tool to generate an manage bazel workspaces for Dart projects.

# Installation

[install-bazel]: https://www.bazel.io/versions/master/docs/install.html

> **NOTE**: dazel requires an existing installation of [bazel][install-bazel]


If you're familiar with [`pub run`][pub_run], then `dazel` is easy. Start by
adding a `dev_dependency` on the `dazel` package.

[pub_run]: https://www.dartlang.org/tools/pub/cmd/pub-run

# Usage

## Setup

You can run `dazel` on a typical `pub` package:

```
my_new_package/
  bin/
  lib/
  web/
  pubspec.yaml
```

```bash
$ cd my_new_package
$ pub run dazel init
```

If you don't have a project, you can use our `workspace` folder of examples. See
`tool/presubmit.dart` for some examples.

## Running

You can `bazel run` files in `bin/`:

```bash
# Assume you have bin/hello.dart
# We automatically generate a "hello_bin" target in your BUILD file.
$ bazel run :hello_bin
```

You can also run a development sever for your web application:

```bash
# Assume you have web/main.dart, and web/index.html.
$ pub run dazel serve
```

Oh, and did we mention support for the [Dart dev compiler][ddc]?

[ddc]: https://github.com/dart-lang/dev_compiler

The dazel server supports both dart code on Dartium and js compiled with DDC.

## Cleaning up

We automatically generate a bunch of file for you - these should not be checked
in to your repository - you can safely ignore them when commiting. Here is an
example snippet you can include in a `.gitignore`:

```gitignore
/bazel-*
.dazel
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

# Customizing builds

Customizing the build behavior of a package is done  by creating a `build.yaml`
file, which describes your configuration. Any packages that use code generation
(or use Transformers when running with `pub`) will need to use a `build.yaml`
to set this up. This includes packages which are dependencies.

## Splitting your package into multiple targets

It is fairly common for a package to want to split up their sources into
multiple targets which each implement a particular feature. Specifically, this
is useful if your package has some sources which are web friendly, and others
which are not.

To split up a package add a `targets` section to your `build.yaml` file, which
defines the different targets that you wish to be generated. This is a map of
target names to configuration. Each target config may contain the following
keys:

- **default**: Optional, defaults to `false`. If `true`, this is the target a
  users package will depend on if they don't have a custom build.yaml file.
  - Exactly one target must be listed as `default: true`.
  - It is also the target you will get if you list the package without a target
    name in the dependencies of one of your targets.
- **sources**: Required. A list of globs to include as sources.
- **exclude_sources**: Optional. A list of globs to to exclude from `sources`.
- **dependencies**: Optional, defaults to empty. The targets that this target
  depends on. The syntax is `$package:$target`.
- **platforms**: Optional, defaults to all platforms. If specified, then this
  indicates which platforms this target is compatible with. Options today are
  `vm` and `web`.
  - If a target is not `web` compatible, it won't be compiled with the dart
    dev compiler, but that is the only effect of this attribute today.
- **builders**: Optional, defaults to empty. The builders to apply to this
  target. These are defined by this package or other packages in the `builders`
  section of their build.yaml.
  - A `List<String>` with the names of the builders run on the library.
- **generate_for**: Optional, defaults to `sources`. The files to treat as
  inputs to all `builders`. Supports glob syntax.


Example `targets` section for a package with two targets and some builders
applied.

```yaml
targets:
  web:
    default: true
    sources:
      - "lib/a.dart"
      - "lib/src/**"
    exclude_sources:
      - "lib/transformer.dart"
      - "lib/src/transformer/**"
    dependencies:
      - "some_package"
      - "some_package:web"
    builders:
      - "some_builder_name"
    generate_for:
      - "lib/a.dart"
  transformer:
    platforms:
      - "vm"
    sources:
      - "lib/transformer.dart"
      - "lib/src/transformer/**"
    dependencies:
      - "barback"
```

## Defining `Builder`s in your package (similar to transformers)

If users of your package need to apply some code generation to their package,
then you can define `Builder`s (from [package:build]
(https://pub.dartlang.org/packages/build)) and have those applied based on the
consuming package `build.yaml`.

You tell dazel about your `Builder`s using the `builders` section of your
`build.yaml`. This is a map of builder names to configuration. Each builder
config may contain the following keys:

- **target**: The name of the target which defines contains your `Builder` class
  definition.
- **import**: Required. The import uri that should be used to import the library
  containing the `Builder` class. This should always be a `package:` uri.
- **builder_factories**: A `List<String>` which contains the names of the
  top-level methods in the imported library which are a function fitting the
  typedef `Builder factoryName(List<String> args)`. When multiple builders are
  used the create a pipeline - the outputs of the first builder become the
  inputs into the next builder.
- **input_extension**: Required. The input extension to treat as primary inputs
  to the builder.:w
- **output_extensions**: Required. The output extensions of this builder.
  - For each file matching `input_extension`, a matching file with each of
    `output_extensions` must be output.

Example `builders` config:

```yaml
targets:
  # The target containing the builder sources.
  _my_builder: # By convention, this is private
    sources:
      - "lib/src/builder/**/*.dart"
      - "lib/builder.dart"
    dependencies:
      - "build"
      - "source_gen"
builders:
  # The actual builder config.
  my_builder:
    target: ":_my_builder"
    import: "package:my_package/builder.dart"
    builder_factories: ["myBuilder"]
    input_extension: ".dart"
    output_extensions:
      - ".my_package.dart"
```
