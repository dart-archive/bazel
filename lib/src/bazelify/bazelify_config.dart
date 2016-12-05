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
      {bool includeWebSources: false, bool enableDdc: true}) {
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
        sources: sources);
  }

  /// Create a [BazelifyConfig] by parsing [configYaml].
  BazelifyConfig.parse(Pubspec pubspec, String configYaml) {
    final config = loadYaml(configYaml);

    var targetConfigs = config['targets'] ?? [];
    for (var targetName in targetConfigs.keys) {
      var targetConfig = targetConfigs[targetName];
      var isDefault = targetConfig['default'] ?? false;
      if (isDefault is! bool) {
        throw new ArgumentError(
            'Got `$isDefault` for `default` but expected a boolean');
      }
      final dependencies = targetConfig['dependencies'] ?? <String>[];
      if (dependencies is! List || dependencies.any((d) => d is! String)) {
        throw new ArgumentError('Got $dependencies for `dependencies` but '
            'expected a List<String>.');
      }
      final platformsConfig = targetConfig['platforms'] ?? _allPlatforms;
      if (platformsConfig is! List ||
          platformsConfig.any((p) => p is! String)) {
        throw new ArgumentError('Got $platformsConfig for `platforms` but '
            'expected a List<String>.');
      }
      final platforms = platformsConfig as List<String>;
      var invalidPlatforms = platforms.where((p) => !_allPlatforms.contains(p));
      if (invalidPlatforms.isNotEmpty) {
        throw new ArgumentError('Got invalid values $invalidPlatforms for '
            '`platforms`. Only $_allPlatforms are supported.');
      }

      dartLibraries[targetName] = new DartLibrary(
        dependencies: dependencies,
        name: targetName,
        enableDdc: platforms.contains(_webPlatform),
        isDefault: isDefault,
        package: pubspec.pubPackageName,
        sources: targetConfig['sources'],
      );
    }

    if (dartLibraries.values.where((l) => l.isDefault).length != 1) {
      throw new ArgumentError('Found no targets with `default: true`. Expected '
          'exactly one.');
    }
  }

  DartLibrary get defaultDartLibrary =>
      dartLibraries.values.singleWhere((l) => l.isDefault);
}
