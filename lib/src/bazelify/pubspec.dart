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

  final _transformers = <Transformer>[];

  /// Create a [Pubspec] by parsing [pubspecYaml].
  Pubspec.parse(String pubspecYaml) : _pubspecContents = loadYaml(pubspecYaml) {
    var transformersConfig = _pubspecContents['transformers'];
    if (transformersConfig == null) return;
    for (var config in transformersConfig) {
      if (config is String) {
        _transformers.add(new Transformer(config));
      } else if (config is Map &&
          config.keys.length == 1 &&
          (config.values.first is Map || config.values.first == null)) {
        _transformers.add(
            new Transformer(config.keys.first, config: config.values.first));
      } else {
        throw new ArgumentError('Unexpected value for transformer config. Got '
            '$config but expected either a String or Map<String, Map> with '
            'exactly one key.');
      }
    }
  }

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

  /// Transformers for the package.
  Iterable<Transformer> get transformers => _transformers;
}

/// A single parsed transformer from a pubspec.
class Transformer {
  /// The name of the transformer as it appears in the pubspec.
  final String name;

  /// The config supplied to the transformer, may be null.
  final Map config;

  Transformer(this.name, {this.config});

  @override
  String toString() => '$name: $config';
}
