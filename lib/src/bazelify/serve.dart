import 'dart:async';
import 'dart:io';

import 'arguments.dart';

Future serve(BazelifyServeArguments args) async {
  print('Building server via bazel...\n');
  var bazelBuildProcess = await Process.start(args.bazelExecutable, [
    'build',
    '${args.pubPackageDir}:${args.target}',
    '--strategy=DartDevCompiler=worker',
    '--strategy=DartSummary=worker',
  ]);
  stdout.addStream(bazelBuildProcess.stdout);
  stderr.addStream(bazelBuildProcess.stderr);
  var bazelExitCode = await bazelBuildProcess.exitCode;
  if (bazelExitCode != 0) {
    exitCode = bazelExitCode;
    return;
  }
  print('\nInitial build finished, starting server...\n');

  var serverProcess = await Process.start('bazel-bin/${args.target}',
      ['--build-target=:${args.target}', '--watch=${args.watch.join(',')}']);
  stdout.addStream(serverProcess.stdout);
  stderr.addStream(serverProcess.stderr);
}
