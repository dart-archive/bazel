import 'dart:async';
import 'dart:io' hide exitCode;

import 'package:archive/archive.dart';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../console.dart';
import '../step_timer.dart';
import 'arguments.dart';
import 'build.dart';
import 'common.dart';
import 'exceptions.dart';

class BuildCommand extends Command {
  BuildCommand() {
    addAppArg(argParser);
    argParser.addOption('output-dir',
        abbr: 'o',
        defaultsTo: 'deploy',
        help: 'The directory to output build outputs to.');
  }

  @override
  String get name => 'build';

  @override
  String get description => 'Builds a dart web app.';

  final timer = new StepTimer();

  @override
  Future<Null> run() async {
    assert(timer == null);
    var commonArgs = await sharedArguments(globalResults);
    if (commonArgs == null) return;

    var app = targetFromAppArgs(argResults, argParser);

    var buildArgs = new BazelifyBuildArguments._(
        bazelExecutable: commonArgs.bazelExecutable,
        pubPackageDir: commonArgs.pubPackageDir,
        outputDir: argResults['output-dir'],
        target: app);

    await timer.run('Building app `${appPathForTarget(buildArgs.target)}`',
        () => build(buildArgs),
        printCompleteOnNewLine: true);
    timer.complete(
        inGreen('Done! See `${buildArgs.outputDir}` dir for build output.'));
  }

  Future build(BazelifyBuildArguments args) async {
    if (p.relative(args.pubPackageDir) != '.') {
      throw new ApplicationFailedException(
          'dazel build only supports running from your top level package '
          'directory.',
          1);
    }
    await timer.run('Running bazel build', () => _bazelBuild(args),
        printCompleteOnNewLine: true);
    var outputDir = new Directory(args.outputDir);
    await timer.run('Deleting old `${args.outputDir}` dir if needed',
        () => _deleteDir(outputDir));
    var entryPoint = await timer.run(
        'Collecting target data', () => _getEntryPointData(args.target));
    var tarPath = 'bazel-bin/${entryPoint.dartFile}.js.tar';
    await timer.run('Expanding tar file at `$tarPath` into `${args.outputDir}`',
        () => _expandTar(tarPath, outputDir, args));
  }

  Future _bazelBuild(BazelifyBuildArguments args) async {
    stdout.writeln();
    var bazelBuildProcess = await Process.start(args.bazelExecutable, [
      'build',
      ':${args.target}',
      // TODO: Remove these, today its needed to disable the sandbox.
      //       see https://github.com/dart-lang/bazel/issues/98.
      '--strategy=DartPackagesDir=standalone',
      '--strategy=Dart2jsCompile=standalone',
    ]);
    stdout.addStream(bazelBuildProcess.stdout);
    stderr.addStream(bazelBuildProcess.stderr);
    var bazelExitCode = await bazelBuildProcess.exitCode;
    if (bazelExitCode != 0) {
      throw new ApplicationFailedException(
          'bazel failed with a non-zero exit code.', bazelExitCode);
    }
    stdout.writeln();
  }

  Future _deleteDir(Directory dir) async {
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  Future<HtmlEntryPoint> _getEntryPointData(String target) {
    var file = new File(appPathForTarget(target));
    return htmlEntryPointFromFile(file, './');
  }

  Future _expandTar(
      String tarPath, Directory outputDir, BazelifyBuildArguments args) async {
    var archive =
        new TarDecoder().decodeBytes(await new File(tarPath).readAsBytes());
    await outputDir.create();
    await Future.wait(archive.files.map((archiveFile) async {
      if (archiveFile.name.endsWith(Platform.pathSeparator)) return null;
      var outputFile = new File(p.join(args.outputDir, archiveFile.name));
      await outputFile.create(recursive: true);
      await outputFile.writeAsBytes(archiveFile.content);
    }));
  }
}

class BazelifyBuildArguments extends BazelifyArguments {
  /// The directory to copy the deployed output to.
  final String outputDir;

  /// The app target to build.
  final String target;

  BazelifyBuildArguments._(
      {String bazelExecutable,
      String pubPackageDir,
      this.outputDir,
      this.target})
      : super(bazelExecutable: bazelExecutable, pubPackageDir: pubPackageDir);
}

final _elapsedRegexp = new RegExp(r'^(0*:)*');
