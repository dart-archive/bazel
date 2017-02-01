import 'dart:async';
import 'dart:io' hide exitCode;

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import 'arguments.dart';
import 'build.dart';
import 'exceptions.dart';

class ServeCommand extends Command {
  ServeCommand() {
    argParser
      ..addOption('watch',
          allowMultiple: true,
          defaultsTo: 'web,lib,pubspec.lock',
          help: 'A list of files/directories to watch for changes and trigger '
              ' builds')
      ..addOption('target',
          defaultsTo: '${BuildFile.ddcServeAllName}',
          help: 'The name of the server build target to run.',
          hide: true);
  }

  @override
  String get name => 'serve';

  @override
  String get description => 'TBD';

  @override
  Future<Null> run() async {
    var commonArgs = await sharedArguments(globalResults);
    if (commonArgs == null) return;

    var serveArgs = new BazelifyServeArguments._(
        bazelExecutable: commonArgs.bazelExecutable,
        pubPackageDir: commonArgs.pubPackageDir,
        target: argResults['target'],
        watch: argResults != null ? argResults['watch'] as List<String> : null);

    await serve(serveArgs);
  }
}

class BazelifyServeArguments extends BazelifyArguments {
  /// The folders and/or files to watch and trigger builds.
  final List<String> watch;

  /// The server build target to run.
  final String target;

  BazelifyServeArguments._({
    String bazelExecutable,
    String pubPackageDir,
    this.target,
    this.watch,
  })
      : super(bazelExecutable: bazelExecutable, pubPackageDir: pubPackageDir);
}

Future serve(BazelifyServeArguments args) async {
  if (p.relative(args.pubPackageDir) != '.') {
    throw new ApplicationFailedException(
        'dazel serve only supports running from your top level package '
        'directory.',
        1);
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
    throw new ApplicationFailedException(
        'bazel failed with a non-zero exit code.', bazelExitCode);
  }
  print('\nInitial build finished, starting server...\n');

  var serverProcess = await Process.start('bazel-bin/${args.target}',
      ['--build-target=:${args.target}', '--watch=${args.watch.join(',')}']);
  stdout.addStream(serverProcess.stdout);
  stderr.addStream(serverProcess.stderr);
}
