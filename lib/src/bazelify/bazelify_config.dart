import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'build.dart';
import 'pubspec.dart';

/// The parsed values from a `bazelify.yaml` file.
class BazelifyConfig {
  /// Supported values for the `platforms` attribute.
  static const _allPlatforms = const [_vmPlatform, _webPlatform];
  static const _vmPlatform = 'vm';
  static const _webPlatform = 'web';

  /// Supported target config options.
  static const _targetOptions = const [
    _default,
    _dependencies,
    _sources,
    _excludeSources,
    _platforms,
  ];
  static const _default = 'default';
  static const _dependencies = 'dependencies';
  static const _sources = 'sources';
  static const _excludeSources = 'exclude_sources';
  static const _platforms = 'platforms';

  /// Returns a parsed [BazelifyConfig] file in [path], if one exists.
  ///
  /// Otherwise uses the default setup.
  static Future<BazelifyConfig> fromPackageDir(Pubspec pubspec, String path,
      {bool includeWebSources: false}) async {
    final configPath = p.join(path, 'bazelify.yaml');
    final file = new File(configPath);
    if (await file.exists()) {
      return new BazelifyConfig.parse(pubspec, await file.readAsString());
    } else {
      return new BazelifyConfig.useDefault(pubspec,
          includeWebSources: includeWebSources);
    }
  }

  /// All the `libraries` defined in a `bazelify.yaml` file.
  final dartLibraries = <String, DartLibrary>{};

  /// The default config if you have no `bazelify.yaml` file.
  BazelifyConfig.useDefault(Pubspec pubspec,
      {bool includeWebSources: false,
      bool enableDdc: true,
      Iterable<String> excludeSources: const []}) {
    var name = pubspec.pubPackageName;
    var sources = ["lib/**"];
    if (includeWebSources) {
      sources.add("web/**");
    }
    dartLibraries[name] = new DartLibrary(
        dependencies: pubspec.dependencies,
        enableDdc: enableDdc,
        isDefault: true,
        name: name,
        package: pubspec.pubPackageName,
        sources: sources,
        excludeSources: excludeSources);
  }

  /// Create a [BazelifyConfig] by parsing [configYaml].
  BazelifyConfig.parse(Pubspec pubspec, String configYaml) {
    final config = loadYaml(configYaml);

    var targetConfigs = config['targets'] ?? [];
    for (var targetName in targetConfigs.keys) {
      var targetConfig = targetConfigs[targetName] as Map<String, dynamic>;

      var invalidOptions = targetConfig.keys.toList()
          ..removeWhere((k) => _targetOptions.contains(k));
      if (invalidOptions.isNotEmpty) {
        throw new ArgumentError('Got invalid options `$invalidOptions` for '
            'target `$targetName`. Only $_targetOptions are supported keys.');
      }

      var isDefault = targetConfig[_default] ?? false;
      if (isDefault is! bool) {
        throw new ArgumentError(
            'Got `$isDefault` for `$_default` but expected a boolean');
      }

      final dependencies = targetConfig[_dependencies] ?? <String>[];
      _checkListOfStringsOrThrow(dependencies, _dependencies);

      final platformsConfig = targetConfig[_platforms] ?? _allPlatforms;
      _checkListOfStringsOrThrow(platformsConfig, _platforms);
      final platforms = platformsConfig as List<String>;
      var invalidPlatforms = platforms.where((p) => !_allPlatforms.contains(p));
      if (invalidPlatforms.isNotEmpty) {
        throw new ArgumentError('Got invalid values $invalidPlatforms for '
            '`$_platforms`. Only $_allPlatforms are supported.');
      }

      final sources = targetConfig[_sources];
      _checkListOfStringsOrThrow(sources, _sources);

      final excludeSources = targetConfig[_excludeSources] ?? [];
      _checkListOfStringsOrThrow(excludeSources, _excludeSources);

      dartLibraries[targetName] = new DartLibrary(
        dependencies: dependencies,
        name: targetName,
        enableDdc: platforms.contains(_webPlatform),
        isDefault: isDefault,
        package: pubspec.pubPackageName,
        excludeSources: excludeSources,
        sources: sources,
      );
    }

    if (dartLibraries.values.where((l) => l.isDefault).length != 1) {
      throw new ArgumentError('Found no targets with `$_default: true`. '
          'Expected exactly one.');
    }
  }

  DartLibrary get defaultDartLibrary =>
      dartLibraries.values.singleWhere((l) => l.isDefault);

  static void _checkListOfStringsOrThrow(value, String option) {
    if (value is! List || value.any((v) => v is! String)) {
      throw new ArgumentError(
        'Got `$value` for `$option` but expected a List<String>.');
    }
  }
}
