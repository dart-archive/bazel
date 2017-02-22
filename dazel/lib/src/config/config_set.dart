import 'dart:async';

import '../bazelify/pubspec.dart';
import 'build_config.dart';

/// The [BuildConfig]s for a package and it's dependencies.
class BuildConfigSet {
  final BuildConfig local;
  final Map<String, BuildConfig> dependencies;

  static Future<BuildConfigSet> forPackages(
          String localPackagePath,
          Map<String, String> dependencyPaths,
          Map<String, Pubspec> dependencyPubspecs) async =>
      new BuildConfigSet(await _readLocalBuildConfig(localPackagePath),
          await _readBuildConfigs(dependencyPaths, dependencyPubspecs));

  BuildConfigSet(this.local, this.dependencies);
}

Future<Map<String, BuildConfig>> _readBuildConfigs(
    Map<String, String> packagePaths, Map<String, Pubspec> pubspecs) async {
  final buildConfigs = <String, BuildConfig>{};
  for (var package in packagePaths.keys) {
    buildConfigs[package] = await BuildConfig.fromPackageDir(
        pubspecs[package], packagePaths[package]);
  }
  return buildConfigs;
}

Future<BuildConfig> _readLocalBuildConfig(String packagePath) async {
  final pubspec = await Pubspec.fromPackageDir(packagePath);
  return BuildConfig.fromPackageDir(pubspec, packagePath,
      includeWebSources: true);
}
