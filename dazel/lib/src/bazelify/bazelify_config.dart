import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'build.dart';
import 'pubspec.dart';

/// The parsed values from a `build.yaml` file.
class BazelifyConfig {
  /// Supported values for the `platforms` attribute.
  static const _allPlatforms = const [_vmPlatform, _webPlatform];
  static const _vmPlatform = 'vm';
  static const _webPlatform = 'web';

  static const _targetOptions = const [
    _builders,
    _default,
    _dependencies,
    _excludeSources,
    _generateFor,
    _platforms,
    _sources,
  ];
  static const _builders = 'builders';
  static const _default = 'default';
  static const _dependencies = 'dependencies';
  static const _excludeSources = 'exclude_sources';
  static const _generateFor = 'generate_for';
  static const _platforms = 'platforms';
  static const _sources = 'sources';

  static const _builderOptions = const [
    _builderFactories,
    _import,
    _inputExtension,
    _outputExtensions,
    _replacesTransformer,
    _target,
  ];
  static const _builderFactories = 'builder_factories';
  static const _import = 'import';
  static const _inputExtension = 'input_extension';
  static const _outputExtensions = 'output_extensions';
  static const _replacesTransformer = 'replaces_transformer';
  static const _target = 'target';

  /// Returns a parsed [BazelifyConfig] file in [path], if one exists.
  ///
  /// Otherwise uses the default setup.
  static Future<BazelifyConfig> fromPackageDir(Pubspec pubspec, String path,
      {bool includeWebSources: false}) async {
    final configPath = p.join(path, 'build.yaml');
    final file = new File(configPath);
    if (await file.exists()) {
      return new BazelifyConfig.parse(pubspec, await file.readAsString(),
          includeWebSources: includeWebSources);
    } else {
      return new BazelifyConfig.useDefault(pubspec,
          includeWebSources: includeWebSources);
    }
  }

  /// All the `builders` defined in a `build.yaml` file.
  final dartBuilderBinaries = <String, DartBuilderBinary>{};

  /// All the `targets` defined in a `build.yaml` file.
  final dartLibraries = <String, DartLibrary>{};

  /// The default config if you have no `build.yaml` file.
  BazelifyConfig.useDefault(Pubspec pubspec,
      {bool includeWebSources: false,
      bool enableDdc: true,
      Iterable<String> excludeSources: const []}) {
    var name = pubspec.pubPackageName;
    var sources = ["lib/**"];
    if (includeWebSources) sources.add("web/**");
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
  BazelifyConfig.parse(Pubspec pubspec, String configYaml,
      {bool includeWebSources: false}) {
    final config = loadYaml(configYaml);

    final Map<String, Map> targetConfigs = config['targets'] ?? {};
    for (var targetName in targetConfigs.keys) {
      var targetConfig = _readMapOrThrow(
          targetConfigs, targetName, _targetOptions, 'target `$targetName`');

      final builders = _readBuildersOrThrow(targetConfig, _builders);

      final dependencies = _readListOfStringsOrThrow(
          targetConfig, _dependencies,
          defaultValue: []);

      final excludeSources = _readListOfStringsOrThrow(
          targetConfig, _excludeSources,
          defaultValue: []);

      var isDefault =
          _readBoolOrThrow(targetConfig, _default, defaultValue: false);

      final platforms = _readListOfStringsOrThrow(targetConfig, _platforms,
          defaultValue: _allPlatforms, validValues: _allPlatforms);

      final sources = _readListOfStringsOrThrow(targetConfig, _sources);

      final generateFor = _readListOfStringsOrThrow(targetConfig, _generateFor,
          allowNull: true);

      dartLibraries[targetName] = new DartLibrary(
        builders: builders,
        dependencies: dependencies,
        enableDdc: platforms.contains(_webPlatform),
        excludeSources: excludeSources,
        generateFor: generateFor,
        isDefault: isDefault,
        name: targetName,
        package: pubspec.pubPackageName,
        sources: sources,
      );
    }

    // Add the default dart library if there are no targets discovered.
    if (dartLibraries.isEmpty) {
      var sources = ["lib/**"];
      if (includeWebSources) sources.add("web/**");
      dartLibraries[pubspec.pubPackageName] = new DartLibrary(
          dependencies: pubspec.dependencies,
          isDefault: true,
          name: pubspec.pubPackageName,
          package: pubspec.pubPackageName,
          sources: sources);
    }

    if (dartLibraries.values.where((l) => l.isDefault).length != 1) {
      throw new ArgumentError('Found no targets with `$_default: true`. '
          'Expected exactly one.');
    }

    final Map<String, Map> builderConfigs = config['builders'] ?? {};
    for (var builderName in builderConfigs.keys) {
      final builderConfig = _readMapOrThrow(builderConfigs, builderName,
          _builderOptions, 'builder `$builderName`',
          defaultValue: <String, dynamic>{});

      final builderFactories =
          _readListOfStringsOrThrow(builderConfig, _builderFactories);
      final import = _readStringOrThrow(builderConfig, _import);
      final inputExtension = _readStringOrThrow(builderConfig, _inputExtension);
      final outputExtensions =
          _readListOfStringsOrThrow(builderConfig, _outputExtensions);
      final replacesTransformer = _readStringOrThrow(
          builderConfig, _replacesTransformer,
          allowNull: true);
      final target = _readStringOrThrow(builderConfig, _target);

      dartBuilderBinaries[builderName] = new DartBuilderBinary(
        builderFactories: builderFactories,
        import: import,
        inputExtension: inputExtension,
        name: builderName,
        outputExtensions: outputExtensions,
        package: pubspec.pubPackageName,
        replacesTransformer: replacesTransformer,
        target: target,
      );
    }
  }

  DartLibrary get defaultDartLibrary =>
      dartLibraries.values.singleWhere((l) => l.isDefault);

  static Map<String, Map<String, dynamic>> _readBuildersOrThrow(
      Map<String, dynamic> options, String option) {
    var values = options[option];
    if (values == null) return null;

    if (values is! List) {
      throw new ArgumentError(
          'Got `$values` for `$option` but expected a List.');
    }

    final normalizedValues = <String, Map<String, dynamic>>{};
    for (var value in values) {
      if (value is String) {
        normalizedValues[value] = {};
      } else if (value is Map) {
        if (value.length == 1) {
          normalizedValues[value.keys.first] = value.values.first;
        } else {
          throw value;
        }
      } else {
        throw new ArgumentError(
            'Got `$value` for builder but expected a String or Map');
      }
    }
    return normalizedValues;
  }

  static List<String> _readListOfStringsOrThrow(
      Map<String, dynamic> options, String option,
      {List<String> defaultValue,
      Iterable<String> validValues,
      bool allowNull: false}) {
    var value = options[option] ?? defaultValue;
    if (value == null && allowNull) return null;

    if (value is! List || value.any((v) => v is! String)) {
      throw new ArgumentError(
          'Got `$value` for `$option` but expected a List<String>.');
    }
    if (validValues != null) {
      var invalidValues = value.where((v) => !validValues.contains(v));
      if (invalidValues.isNotEmpty) {
        throw new ArgumentError('Got invalid values ``$invalidValues` for '
            '`$option`. Only `$validValues` are supported.');
      }
    }
    return value;
  }

  static Map<String, dynamic> _readMapOrThrow(Map<String, dynamic> options,
      String option, Iterable<String> validKeys, String description,
      {Map<String, dynamic> defaultValue}) {
    var value = options[option] ?? defaultValue;
    if (value is! Map) {
      throw new ArgumentError('Invalid options for `$option`, got `$value` but '
          'expected a Map.');
    }
    var mapValue = value as Map<String, dynamic>;
    var invalidOptions = mapValue.keys.toList()
      ..removeWhere((k) => validKeys.contains(k));
    if (invalidOptions.isNotEmpty) {
      throw new ArgumentError('Got invalid options `$invalidOptions` for '
          '$description. Only `$validKeys` are supported keys.');
    }
    return mapValue;
  }

  static String _readStringOrThrow(Map<String, dynamic> options, String option,
      {String defaultValue, bool allowNull: false}) {
    var value = options[option];
    if (value == null && allowNull) return null;
    if (value is! String) {
      throw new ArgumentError(
          'Expected a String for `$option` but got `$value`.');
    }
    return value;
  }

  static bool _readBoolOrThrow(Map<String, dynamic> options, String option,
      {bool defaultValue}) {
    var value = options[option] ?? defaultValue;
    if (value is! bool) {
      throw new ArgumentError(
          'Expected a boolean for `$option` but got `$value`.');
    }
    return value;
  }
}
