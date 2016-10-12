import 'dart:async';
import 'dart:io';

import 'package:bazel/src/arguments.dart';
import 'package:bazel/src/bazelify.dart';
import 'package:package_config/packages_file.dart';
import 'package:path/path.dart' as path;

Future<Null> main(List<String> args) async {
  // Parse into an object.
  BazelifyArguments arguments;
  try {
    arguments = new BazelifyArguments.parse(args);
  } on ArgumentError catch (e) {
    if (e.name != null) {
      _printArgumentError(e);
    } else {
      rethrow;
    }
    _printUsage();
    exit(1);
  }

  // Massage the arguments based on defaults.
  arguments = await arguments.resolve();

  // Store and change the CWD.
  var previousCurrent = Directory.current;
  Directory.current = new Directory(arguments.pubPackageDir);

  // Run "pub get".
  await Process.run(arguments.pubExecutable, const ['get']);

  // Revert back to the old CWD
  Directory.current = previousCurrent;

  // Read the ".packages" file.
  final packages = new File(path.join(arguments.pubPackageDir, '.packages'));
  if (!await packages.exists()) {
    throw new StateError('No .packages found at "${packages.absolute.path}"');
  }

  // Write a packages.bzl file and a .bazelify directory.
  await generateBzl(
    arguments.pubPackageDir,
    pubBazelRepos(
      parse(
        await packages.readAsBytes(),
        packages.uri,
      ),
    ),
  );

  final absolute = path.absolute(arguments.pubPackageDir);
  print('Generated pacakges.bzl, WORKSPACE, BUILD files for $absolute');
}

void _printArgumentError(ArgumentError e) {
  print('Invalid arguments: ${e.message}');
}

void _printUsage() {
  print(BazelifyArguments.getUsage());
}
