import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:package_config/packages_file.dart';

import 'arguments.dart';
import 'build.dart';
import 'macro.dart';
import 'pubspec.dart';
import 'workspace.dart';

/// Runs `bazelify` as specified in [arguments].
Future<Null> generate(BazelifyArguments arguments) async {
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
