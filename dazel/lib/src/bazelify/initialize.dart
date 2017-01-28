import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:package_config/packages_file.dart' as packages_file;
import 'package:path/path.dart' as p;
import 'package:which/which.dart';
import 'package:yaml/yaml.dart';

import '../step_timer.dart';
import 'arguments.dart';
import 'bazelify_config.dart';
import 'build.dart';
import 'macro.dart';
import 'pubspec.dart';
import 'workspace.dart';

/// Arguments when running `bazelify init`, which adds Bazel support on top of
/// pub.
class BazelifyInitArguments extends BazelifyArguments {
  /// A configured [DartRulesSource] for a `WORKSPACE`.
  final DartRulesSource dartRulesSource;

  /// A path to find 'pub'.
  ///
  /// If `null` implicitly defaults to your PATH.
  final String pubExecutable;

  /// Create a new set of arguments for how to run `bazelify init`.
  ///
  /// Will be executed locally to where [pubPackageDir] is. For example,
  /// assuming the following directory structure, the directory could be
  /// `projects/foo_bar`:
  ///
  ///   ```
  ///   - projects
  ///     - foo_bar
  ///       pubspec.yaml
  ///   ```
  ///
  /// Options:
  /// - [bazelExecutable]: Where to find `bazel`. Defaults to your PATH.
  /// - [pubExecutable]: Where to find `pub`. Defaults to your PATH.
  /// - [pubPackageDir]: Where a package with a `pubspec.yaml` is. Defaults to
  ///   the current working directory.
  BazelifyInitArguments._({
    String bazelExecutable,
    this.dartRulesSource: DartRulesSource.stable,
    this.pubExecutable,
    String pubPackageDir,
  })
      : super(bazelExecutable: bazelExecutable, pubPackageDir: pubPackageDir);
}

class InitCommand extends Command {
  InitCommand() {
    argParser
      ..addOption(
        'rules-commit',
        help: 'A commit SHA on dart-lang/rules_dart to use.',
      )
      ..addOption(
        'rules-local',
        help: 'A path to a local version of rules_dart.',
      )
      ..addOption(
        'rules-tag',
        help: 'A tagged version on dart-lang/rules_dart to use.',
      )
      ..addOption(
        'pub',
        help: 'A path to the "pub" executable. Defaults to your PATH.',
      );
  }

  @override
  String get name => 'init';

  @override
  String get description => 'TBD';

  @override
  Future<Null> run() async {
    var commonArgs = await sharedArguments(globalResults);
    if (commonArgs == null) return;

    var rulesTypes = ['rules-commit', 'rules-tag', 'rules-local'];
    var setRules = <String, String>{};
    for (var type in rulesTypes) {
      if (argResults.wasParsed(type)) {
        setRules[type] = argResults[type];
      }
    }

    DartRulesSource source;
    if (setRules.isEmpty) {
      source = DartRulesSource.stable;
    } else if (setRules.length == 1) {
      var key = setRules.keys.single;
      var value = setRules[key];
      switch (key) {
        case 'rules-commit':
          source = new DartRulesSource.commit(value);
          break;
        case 'rules-tag':
          source = new DartRulesSource.tag(value);
          break;
        case 'rules-local':
          source = new DartRulesSource.local(value);
          break;
        default:
          throw new UnsupportedError('No clue how this happened');
      }
    } else {
      this.usageException(
          'No more than one can be used: ${rulesTypes.join(', ')}');
    }

    String pubResolved =
        argResults.command != null ? argResults.command['pub'] : null;
    if (pubResolved == null) {
      pubResolved = await which('pub');
    } else {
      if (!await FileSystemEntity.isFile(pubResolved)) {
        throw new StateError('No "pub" found at "$pubResolved"');
      }
    }

    var initArgs = new BazelifyInitArguments._(
        bazelExecutable: commonArgs.bazelExecutable,
        dartRulesSource: source,
        pubExecutable: pubResolved,
        pubPackageDir: commonArgs.pubPackageDir);

    await new _Initialize(initArgs).run();
  }
}

/// Where to retrieve the `rules_dart`.
abstract class DartRulesSource {
  /// The default version of [DartRulesSource] if not otherwise specified.
  static const DartRulesSource stable = const DartRulesSource.tag('v0.2.3');

  /// Use a git [commit].
  const factory DartRulesSource.commit(String commit) = _GitCommitRulesSource;

  /// Use a file [path].
  const factory DartRulesSource.local(String path) = _LocalRulesSource;

  /// Use a git [tag].
  const factory DartRulesSource.tag(String tag) = _GitTagRulesSource;
}

class _LocalRulesSource implements DartRulesSource {
  final String _path;

  const _LocalRulesSource(this._path);

  @override
  String toString() => 'local_repository(\n'
      '    name = "io_bazel_rules_dart",\n'
      '    path = "$_path",\n'
      ')\n';
}

class _GitCommitRulesSource implements DartRulesSource {
  final String _commit;

  const _GitCommitRulesSource(this._commit);

  @override
  String toString() => 'git_repository(\n'
      '    name = "io_bazel_rules_dart",\n'
      '    remote = "https://github.com/dart-lang/rules_dart",\n'
      '    commit = "$_commit",\n'
      ')\n';
}

class _GitTagRulesSource implements DartRulesSource {
  final String _tag;

  const _GitTagRulesSource(this._tag);

  @override
  String toString() => 'git_repository(\n'
      '    name = "io_bazel_rules_dart",\n'
      '    remote = "https://github.com/dart-lang/rules_dart",\n'
      '    tag = "$_tag",\n'
      ')\n';
}

class _Initialize {
  final BazelifyInitArguments arguments;

  _Initialize(this.arguments);

  Future<Null> run() async {
    final timer = new StepTimer();
    await timer.run('pub get', _pubGetInPackage);
    final packagePaths = await _readPackagePaths();
    final pubspecs = await _readPubspecs(packagePaths);
    final bazelifyConfigs = await _readBazelifyConfigs(packagePaths, pubspecs);
    await timer.run('create .bazelify',
        () => _createBazelifyDir(packagePaths, pubspecs, bazelifyConfigs));
    await timer.run('create packages.bzl, build, and workspace',
        () => _writeBazelFiles(packagePaths, bazelifyConfigs));
    await timer.run('scan for analysis options', _suggestAnalyzerExcludes);
    timer.printTimings();
  }

  Future<Null> _pubGetInPackage() async {
    final previousDirectory = Directory.current;
    Directory.current = new Directory(arguments.pubPackageDir);
    await Process.run(arguments.pubExecutable, const ['get']);
    Directory.current = previousDirectory;
  }

  Future<Null> _createBazelifyDir(
      Map<String, String> packagePaths,
      Map<String, Pubspec> pubspecs,
      Map<String, BazelifyConfig> bazelifyConfigs) async {
    final bazelifyPath = p.join(arguments.pubPackageDir, '.bazelify');
    await _createEmptyDir(bazelifyPath);
    await _writePackageBuildFiles(
        bazelifyPath, packagePaths, pubspecs, bazelifyConfigs);
  }

  Future<Null> _writeBazelFiles(Map<String, String> packagePaths,
      Map<String, BazelifyConfig> bazelifyConfigs) async {
    await _writePackagesBzl(packagePaths);
    await _writeWorkspaceFile();
    await _writeBuildFile(bazelifyConfigs);
  }

  Future<Map<String, String>> _readPackagePaths() async {
    final packagesFilePath = p.join(arguments.pubPackageDir, '.packages');
    var packageUris = packages_file.parse(
      await new File(packagesFilePath).readAsBytes(),
      Uri.parse(packagesFilePath),
    );
    var packagePaths = <String, String>{};
    for (var package in packageUris.keys) {
      var localPath = packageUris[package].toFilePath();
      localPath = localPath.substring(0, localPath.length - 'lib/'.length);
      packagePaths[package] = localPath;
    }
    return packagePaths;
  }

  Future<Map<String, BazelifyConfig>> _readBazelifyConfigs(
      Map<String, String> packagePaths, Map<String, Pubspec> pubspecs) async {
    final bazelifyConfigs = <String, BazelifyConfig>{};
    for (var package in packagePaths.keys) {
      bazelifyConfigs[package] = await BazelifyConfig.fromPackageDir(
          pubspecs[package], packagePaths[package]);
    }
    return bazelifyConfigs;
  }

  Future<Map<String, Pubspec>> _readPubspecs(
      Map<String, String> packagePaths) async {
    final pubspecs = <String, Pubspec>{};
    for (var package in packagePaths.keys) {
      pubspecs[package] = await Pubspec.fromPackageDir(packagePaths[package]);
    }
    return pubspecs;
  }

  Future<Null> _createEmptyDir(String dirPath) async {
    final dir = new Directory(dirPath);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    await dir.create(recursive: true);
  }

  Future<Null> _writePackageBuildFiles(
      String bazelifyPath,
      Map<String, String> packagePaths,
      Map<String, Pubspec> pubspecs,
      Map<String, BazelifyConfig> bazelifyConfigs) async {
    for (final package in packagePaths.keys) {
      final buildFilePath = p.join(bazelifyPath, '$package.BUILD');
      final packageDir = packagePaths[package];
      var buildFile = await BuildFile.fromPackageDir(
          packageDir, pubspecs[package], bazelifyConfigs);
      await new File(buildFilePath).writeAsString('$buildFile');
    }
  }

  Future<Null> _writePackagesBzl(Map<String, String> packagePaths) async {
    final pubspec = await Pubspec.fromPackageDir(arguments.pubPackageDir);
    final macroFile = new BazelMacroFile.fromPackages(
      pubspec.pubPackageName,
      packagePaths.keys,
      (package) => packagePaths[package],
    );
    final packagesBzl = p.join(arguments.pubPackageDir, 'packages.bzl');
    await new File(packagesBzl).writeAsString('$macroFile');
  }

  Future<Null> _writeWorkspaceFile() async {
    final workspaceFile = p.join(arguments.pubPackageDir, 'WORKSPACE');
    final workspace = new Workspace.fromDartSource(arguments.dartRulesSource);
    await new File(workspaceFile).writeAsString('$workspace');
  }

  Future<Null> _writeBuildFile(
      Map<String, BazelifyConfig> bazelifyConfigs) async {
    final packagePath = arguments.pubPackageDir;
    final pubspec = await Pubspec.fromPackageDir(packagePath);
    final bazelifyConfig = await BazelifyConfig
        .fromPackageDir(pubspec, packagePath, includeWebSources: true);
    bazelifyConfigs[pubspec.pubPackageName] = bazelifyConfig;
    final rootBuild = await BuildFile.fromPackageDir(
        arguments.pubPackageDir, pubspec, bazelifyConfigs);
    final rootBuildPath = p.join(arguments.pubPackageDir, 'BUILD');
    await new File(rootBuildPath).writeAsString('$rootBuild');
  }

  /// Checks for the presence of an analysis_options which excludes bazel
  /// generated directories.
  ///
  /// If no analysis options exist, a sane default will be created. If an
  /// analysis options exist but does not include 'bazel-*' in the excluded
  /// files a help message will be printed.
  Future<Null> _suggestAnalyzerExcludes() async {
    final analysisOptionsFile = await _findAnalysisOptions();
    final exampleExclude = '''
analyzer:
  strong-mode: true
  exclude:
    - bazel-*
''';
    if (analysisOptionsFile == null) {
      final analysisOptionsPath =
          p.join(arguments.pubPackageDir, 'analysis_options.yaml');
      await new File(analysisOptionsPath).writeAsString(exampleExclude);
    } else {
      final analysisOptions =
          loadYaml(await analysisOptionsFile.readAsString());
      final analyzerConfig = analysisOptions['analyzer'];
      final excludes =
          analyzerConfig == null ? null : analyzerConfig['exclude'];
      if (excludes == null || !excludes.contains('bazel-*')) {
        print('Bazel will create directories with symlinked dart files which '
            'will impact the analysis server.\n'
            'We recommend you add `bazel-*` to the excluded files in your '
            'analysis options.\n'
            'Found analysis options at:\n'
            '${p.absolute(analysisOptionsFile.path)}\n\nFor example:\n'
            '$exampleExclude');
      }
    }
  }

  /// Searchs up in directories starting with the pubPackageDir until a
  /// '.analysis_options' or 'analysis_options.yaml' is found, or null if no
  /// such file exists.
  Future<File> _findAnalysisOptions() async {
    File analysisOptionsFile;
    var searchPath = arguments.pubPackageDir;
    while (analysisOptionsFile == null) {
      analysisOptionsFile ??=
          await _findExistingFile(p.join(searchPath, '.analysis_options'));
      analysisOptionsFile ??=
          await _findExistingFile(p.join(searchPath, 'analysis_options.yaml'));
      if (searchPath == p.dirname(searchPath)) break;
      searchPath = p.dirname(searchPath);
    }
    return analysisOptionsFile;
  }

  /// Returns a [File] if it exists at [path], otherwise return null.
  Future<File> _findExistingFile(String path) async {
    var file = new File(path);
    if (await file.exists()) return file;
    return null;
  }
}
