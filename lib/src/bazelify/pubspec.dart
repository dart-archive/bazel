import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'build.dart';

/// The parsed values from a Dart `pubspec.yaml` file.
class Pubspec {
  /// Returns a parsed [Pubspec] file in [path], if one exists.
  ///
  /// Otherwise throws [FileSystemException].
  static Future<Pubspec> fromPackageDir(String path) async {
    final pubspec = p.join(path, 'pubspec.yaml');
    final file = new File(pubspec);
    if (await file.exists()) {
      return new Pubspec.parse(await file.readAsString());
    }
    throw new FileSystemException('No file found', p.absolute(pubspec));
  }

  final Map _pubspecContents;

  /// Create a [Pubspec] by parsing [pubspecYaml].
  Pubspec.parse(String pubspecYaml) : _pubspecContents = loadYaml(pubspecYaml);

  /// Dependencies for a pub package.
  ///
  /// Maps directly to the `dependencies` list in `pubspec.yaml`.
  Iterable<String> get dependencies => _deps('dependencies');

  /// Development dependencies for a pub package.
  ///
  /// Maps directly to the `dev_dependencies` list in `pubspec.yaml`.
  Iterable<String> get devDependencies => _deps('dev_dependencies');

  /// Dependencies for a Bazel library.
  ///
  /// For the following input:
  ///     ```yaml
  ///     dependencies:
  ///       args:
  ///       path:
  ///     ```
  ///
  /// Returns:
  ///     [
  ///       '@args:args',
  ///       '@path:path',
  ///     ]
  Iterable<String> get depsAsBazelTargets =>
      pubPackagesToBazelTargets(dependencies);

  /// Development dependencies for a Bazel library.
  ///
  /// These are not required to use the library, but rather to develop it. One
  /// example would be a testing library (such as `package:test`).
  ///
  /// See also: [dependencies].
  Iterable<String> get devDepsAsBazelTargets =>
      pubPackagesToBazelTargets(devDependencies);

  // Extract dependencies.
  Iterable<String> _deps(String flavor) =>
      (_pubspecContents[flavor] ?? const {}).keys as Iterable<String>;

  /// Name of the package.
  String get pubPackageName => _pubspecContents['name'];
}
