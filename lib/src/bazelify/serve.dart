import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'arguments.dart';

Future serve(BazelifyServeArguments args) async {
  if (p.relative(args.pubPackageDir) != '.') {
    print('bazelify serve only supports running from your top level package '
        'directory.');
    exitCode = 1;
    return;
  }

  print('Building server via bazel...\n');
  var bazelBuildProcess = await Process.start(args.bazelExecutable, [
    'build',
    ':${args.target}',
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
