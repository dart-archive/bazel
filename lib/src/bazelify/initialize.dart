import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:package_config/packages_file.dart';
import 'package:path/path.dart' as p;
import 'package:which/which.dart';

import 'arguments.dart';
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
          source = new DartRulesSource.tag(value);
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

    await initalize(initArgs);
  }
}

/// Where to retrieve the `rules_dart`.
abstract class DartRulesSource {
  /// The default version of [DartRulesSource] if not otherwise specified.
  static const DartRulesSource stable = const DartRulesSource.tag('0.1.1');

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

/// Runs `bazelify init` as specified in [arguments].
Future<Null> initalize(BazelifyInitArguments arguments) async {
  // Start timing.
  final timings = <String, Duration>{};
  final stopwatch = new Stopwatch()..start();

  // Store and change the CWD.
  var previousCurrent = Directory.current;
  Directory.current = new Directory(arguments.pubPackageDir);

  // Run "pub get".
  await Process.run(arguments.pubExecutable, const ['get']);
  timings['pub get'] = stopwatch.elapsed;
  stopwatch.reset();

  // Revert back to the old CWD
  Directory.current = previousCurrent;

  // Read the package's pubspec and the generated .packages file.
  final pubspec = await Pubspec.fromPackageDir(arguments.pubPackageDir);
  final packagesFilePath = p.join(arguments.pubPackageDir, '.packages');
  final packages = parse(
    await new File(packagesFilePath).readAsBytes(),
    Uri.parse(packagesFilePath),
  );

  // Clean and re-build the .bazelify folder.
  final bazelifyPath = p.join(arguments.pubPackageDir, '.bazelify');
  final bazelifyDir = new Directory(bazelifyPath);
  if (await bazelifyDir.exists()) {
    await bazelifyDir.delete(recursive: true);
  }
  await bazelifyDir.create(recursive: true);

  // Store the current path.
  final packageToPath = <String, String>{};
  for (final package in packages.keys) {
    // Get ready to create a <name>.BUILD.
    final buildFilePath = p.join(bazelifyPath, '$package.BUILD');
    var localPath = packages[package].toFilePath();
    localPath = localPath.substring(0, localPath.length - 'lib/'.length);
    packageToPath[package] = localPath;

    // Create a new build file for this directory and write to disk.
    final newBuildFile = await BuildFile.fromPackageDir(localPath);
    await new File(buildFilePath).writeAsString(newBuildFile.toString());
  }
  timings['create .bazelify'] = stopwatch.elapsed;
  stopwatch.reset();

  // Create a packages.bzl file and write to disk.
  final macroFile = new BazelMacroFile.fromPackages(
    pubspec.pubPackageName,
    packages.keys,
    (package) => packageToPath[package],
  );
  final packagesBzl = p.join(arguments.pubPackageDir, 'packages.bzl');
  await new File(packagesBzl).writeAsString(macroFile.toString());

  // Create a WORKSPACE file.
  final workspaceFile = p.join(arguments.pubPackageDir, 'WORKSPACE');
  final workspace = new Workspace.fromDartSource(arguments.dartRulesSource);
  await new File(workspaceFile).writeAsString(workspace.toString());

  // Create a BUILD file.
  final rootBuild = await BuildFile.fromPackageDir(arguments.pubPackageDir);
  final rootBuildPath = p.join(arguments.pubPackageDir, 'BUILD');
  await new File(rootBuildPath).writeAsString(rootBuild.toString());

  // Done!
  timings['create packages.bzl, build, and workspace'] = stopwatch.elapsed;

  // Print timings.
  timings.forEach((name, duration) {
    print('$name took ${duration.inMilliseconds}ms');
  });
}
