import 'dart:async';
import 'dart:io';

import 'package:package_config/packages_file.dart';
import 'package:path/path.dart' as path;

import 'arguments.dart';
import 'bazelify.dart';

Future<Null> work(BazelifyArguments arguments) async {
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
