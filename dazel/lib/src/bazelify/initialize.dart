import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:package_config/packages_file.dart' as packages_file;
import 'package:path/path.dart' as p;
import 'package:which/which.dart';
import 'package:yaml/yaml.dart';

import '../config/config_set.dart';
import '../console.dart';
import '../step_timer.dart';
import 'arguments.dart';
import 'build.dart';
import 'codegen_rules.dart';
import 'exceptions.dart';
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
  static const DartRulesSource stable = const DartRulesSource.tag('v0.4.1');

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
    await timer.run('Running pub get', _pubGetInPackage);
    final packagePaths = await _readPackagePaths();
    final pubspecs = await _readPubspecs(packagePaths);
    final buildConfigs = await BuildConfigSet.forPackages(
        arguments.pubPackageDir, packagePaths, pubspecs);
    await timer.run('Creating .dazel directory',
        () => _createDazelDir(packagePaths, pubspecs, buildConfigs));
    await timer.run('Creating packages.bzl, build, and workspace',
        () => _writeBazelFiles(packagePaths, buildConfigs));
    await timer.run('Scanning for analysis options', _suggestAnalyzerExcludes,
        printCompleteOnNewLine: true);
    await timer.run('Scanning for .gitignore options', _suggestGitIgnoreOptions,
        printCompleteOnNewLine: true);
    timer.complete(inGreen('Done!'));
  }

  Future<Null> _pubGetInPackage() async {
    final previousDirectory = Directory.current;
    Directory.current = new Directory(arguments.pubPackageDir);
    await Process.run(arguments.pubExecutable, const ['get']);
    Directory.current = previousDirectory;
  }

  Future<Null> _createDazelDir(Map<String, String> packagePaths,
      Map<String, Pubspec> pubspecs, BuildConfigSet buildConfigs) async {
    final dazelDir = p.join(arguments.pubPackageDir, '.dazel');
    await _createEmptyDir(dazelDir);
    await _writePackageBuildFiles(
        dazelDir, packagePaths, pubspecs, buildConfigs);
    await _writePackageCodegenRules(dazelDir, buildConfigs);
  }

  Future<Null> _writeBazelFiles(
      Map<String, String> packagePaths, BuildConfigSet buildConfigs) async {
    await _writePackagesBzl(packagePaths, buildConfigs);
    await _writeWorkspaceFile();
    await _writeBuildFile(buildConfigs);
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
      String dazelDir,
      Map<String, String> packagePaths,
      Map<String, Pubspec> pubspecs,
      BuildConfigSet buildConfigs) async {
    for (final package in packagePaths.keys) {
      final buildFilePath = p.join(dazelDir, 'pub_$package.BUILD');
      final packageDir = packagePaths[package];
      var buildFile = await BuildFile.fromPackageDir(
          packageDir, pubspecs[package], buildConfigs);
      await new File(buildFilePath).writeAsString('$buildFile');
    }
  }

  Future<Null> _writePackageCodegenRules(
      String dazelDir, BuildConfigSet buildConfigs) async {
    if (!buildConfigs.hasCodegen) return;
    final codegenDir = p.join(dazelDir, 'codegen');
    await _createEmptyDir(codegenDir);
    await new File(p.join(codegenDir, 'BUILD')).writeAsString('#EMPTY\n');
    for (final package in buildConfigs.dependencies.keys) {
      final buildConfig = buildConfigs.dependencies[package];
      if (buildConfig.dartBuilderBinaries.isEmpty) continue;
      final rulesFilePath = p.join(codegenDir, 'pub_$package.codegen.bzl');
      final rulesFile = new CodegenRulesFile(buildConfig.dartBuilderBinaries);
      await new File(rulesFilePath).writeAsString('$rulesFile');
    }
  }

  Future<Null> _writePackagesBzl(
      Map<String, String> packagePaths, BuildConfigSet buildConfigs) async {
    final pubspec = await Pubspec.fromPackageDir(arguments.pubPackageDir);
    final macroFile = new BazelMacroFile.fromPackages(
      pubspec.pubPackageName,
      packagePaths.keys,
      buildConfigs,
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

  Future<Null> _writeBuildFile(BuildConfigSet buildConfigs) async {
    final packagePath = arguments.pubPackageDir;
    final pubspec = await Pubspec.fromPackageDir(packagePath);
    final rootBuild = await BuildFile.fromPackageDir(
        arguments.pubPackageDir, pubspec, buildConfigs);
    final rootBuildPath = p.join(arguments.pubPackageDir, 'BUILD');
    try {
      await new File(rootBuildPath).writeAsString('$rootBuild');
    } on FileSystemException catch (_) {
      if (await FileSystemEntity.isDirectory(rootBuildPath)) {
        throw new ApplicationFailedException(
            'Found existing `BUILD` (or `build`) directory in your package, '
            'please delete or rename this directory and re-run `dazel init`, '
            'so that a BUILD file may be created.',
            1);
      } else {
        rethrow;
      }
    }
  }

  /// Checks for the presence of an analysis_options which excludes bazel
  /// generated directories.
  ///
  /// If no analysis options exist, a sane default will be created. If an
  /// analysis options exist but does not include 'bazel-*' in the excluded
  /// files a help message will be printed.
  Future<Null> _suggestAnalyzerExcludes() async {
    final analysisOptionsFile = await _findConfigFile([
      '.analysis_options',
      'analysis_options.yaml',
    ]);
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
      try {
        final analysisOptions =
            loadYaml(await analysisOptionsFile.readAsString()) ?? {};
        final analyzerConfig = analysisOptions['analyzer'] ?? {};
        final excludes = analyzerConfig['exclude'];
        if (excludes == null || !excludes.contains('bazel-*')) {
          print(inYellow(
              'Bazel will create directories with symlinked dart files which '
              'will impact the analysis server.\n'
              'We recommend you add `bazel-*` to the excluded files in your '
              'analysis options.\n'
              'Found analysis options at:\n'
              '${p.absolute(analysisOptionsFile.path)}\n\nFor example:\n'
              '$exampleExclude'));
        }
      } on YamlException catch (e) {
        print(inRed('Found invalid analysis options file at '
            '${analysisOptionsFile.path}:'));
        print(inRed('$e'));
      }
    }
  }

  Future<Null> _suggestGitIgnoreOptions() async {
    final gitIgnoreFile = await _findConfigFile(['.gitignore']);
    // If no gitignore just return, they probably are not using git at all.
    if (gitIgnoreFile == null) return;

    var expectedLines = ['.dazel', 'bazel-*', 'BUILD', 'WORKSPACE'];
    var packageRelativeToGitignore = p.relative(arguments.pubPackageDir,
        from: p.dirname(gitIgnoreFile.path));
    for (var line in await gitIgnoreFile.readAsLines()) {
      expectedLines.remove(line);
      if (line.startsWith(packageRelativeToGitignore)) {
        expectedLines
            .remove(line.substring(packageRelativeToGitignore.length + 1));
      }
    }
    if (expectedLines.isNotEmpty) {
      var message = new StringBuffer()
        ..writeln('It is recommended that you add the following lines to your '
            '`${p.relative(gitIgnoreFile.path, from: arguments.pubPackageDir)}` '
            'file :')
        ..writeln('');
      for (var line in expectedLines) {
        message.writeln(p.normalize(p.join(packageRelativeToGitignore, line)));
      }
      message
        ..writeln('')
        ..writeln('These are directories created by bazel and dazel, and '
            'should not be checked in.');
      print(inYellow('$message'));
    }
  }

  /// Searchs up in directories starting with the pubPackageDir until one of
  /// [supportedFileNames] is found, or null if no such file exists.
  Future<File> _findConfigFile(List<String> supportedFileNames) async {
    File file;
    var searchPath = arguments.pubPackageDir;
    while (file == null) {
      for (var fileName in supportedFileNames) {
        file ??= await _findExistingFile(p.join(searchPath, fileName));
      }
      if (searchPath == p.dirname(searchPath)) break;
      searchPath = p.dirname(searchPath);
    }
    return file;
  }

  /// Returns a [File] if it exists at [path], otherwise return null.
  Future<File> _findExistingFile(String path) async {
    var file = new File(path);
    if (await file.exists()) return file;
    return null;
  }
}
