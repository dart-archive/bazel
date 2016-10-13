import 'package:yaml/yaml.dart';

/// The parsed values from a Dart pubspec.yaml file.
class Pubspec {
  final Map pubspecContents;

  Pubspec(String pubspecYaml) : pubspecContents = loadYaml(pubspecYaml);

  /// Dependencies for a Bazel library from [pubspecContents].
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
  Iterable<String> get deps => _deps('dependencies');

  /// Generate a list of dev dependencies for a Bazel library from
  /// [pubspecContents].
  ///
  /// See [deps].
  Iterable<String> get devDeps => _deps('dev_dependencies');

  Iterable<String> _deps(String flavor) {
    final dependencies = pubspecContents[flavor] ?? const {};
    return (dependencies as Map).keys.map((d) => '@$d//:$d');
  }

  String get packageName => pubspecContents['name'];
}
