#!/usr/bin/env dart
import 'dart:io';

import 'package:path/path.dart' as p;

main() {
  // Change the CWD.
  print('Changing CWD...');
  Directory.current = p.join(p.current, 'workspace');

  print('Running pub get...');
  var pubGetResult = Process.runSync('pub', ['get']);
  if (pubGetResult.exitCode != 0) {
    print('Pub get failed');
    exit(1);
  }

  // Run dazel.
  print('Running dazel...');
  var result = Process.runSync('pub', ['run', 'dazel', 'init']);
  if (result.stderr.isNotEmpty || result.exitCode != 0) {
    print('ERROR: ${result.stderr}');
    exit(1);
  }
  print(result.stdout);

  result = bazel(['version']);
  print(result.stdout);

  print('Cleaning...');
  result = bazel(['clean']);

  testRunningGetCwd();
  // TODO: Not finding the NG2 web app
  //testBuildingNg2App();
  testRunningDartFmt();

  print('\nPASS');
}

void testRunningGetCwd() {
  print('Running a VM binary');
  var result = bazel(['run', ':get_cwd']);
  if (!result.stderr.contains('Running command line: ')) {
    print('Error: ${result.stderr}');
    exit(1);
  }
}

void testBuildingNg2App() {
  print('Building a Web app...');
  var result = bazel(['build', 'ng2_app:all']);
  if (!result.stderr.contains('Compiling with dart2js //ng2_app:ng2_app')) {
    print('Error: ${result.stderr}');
    exit(1);
  }
}

void testRunningDartFmt() {
  print('Run the pre-built dart_style:format binary...');
  var result = bazel(['run', 'run_dartfmt']);
  if (!result.stderr.contains('run_dartfmt @dart_style//:format')) {
    print('Error: ${result.stderr}');
    exit(1);
  }
}

ProcessResult bazel(List<String> args, {int expectedExitCode: 0}) {
  var command = args.removeAt(0);
  var result =
      Process.runSync('bazel', [command, '--noshow_progress']..addAll(args));
  if (result.exitCode != expectedExitCode) {
    print('Error: Could not call `bazel $command ${args.join(' ')}`. '
        'RC ${result.exitCode}');
    exit(1);
  }
  return result;
}
