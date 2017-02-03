import 'dart:async';
import 'dart:io' hide exitCode;

import 'package:archive/archive.dart';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import 'arguments.dart';
import 'build.dart';
import 'exceptions.dart';

class BuildCommand extends Command {
  BuildCommand() {
    argParser
      ..addOption('app',
          help: 'The name of the app target to build, this is the name of the '
              'html file for the app. This argument may be provided as a '
              'positional argument as well.')
      ..addOption('output-dir',
          abbr: 'o',
          defaultsTo: 'deploy',
          help: 'The directory to output build outputs to.');
  }

  @override
  String get name => 'build';

  @override
  String get description => 'Builds a dart web app.';

  final watch = new Stopwatch();

  @override
  Future<Null> run() async {
    assert(!watch.isRunning);
    watch.start();
    var commonArgs = await sharedArguments(globalResults);
    if (commonArgs == null) return;

    var app = argResults['app'] as String;
    // Support providing `app` as a positional argument.
    if (app == null && argResults.rest.length == 1) {
      app = argResults.rest.first;
    } else {
      throw new ApplicationFailedException(
          'Missing required argument `app`:\n${argParser.usage}', 1);
    }
    // Target name doesn't have `.html`, but we want support for that for users.
    if (app.endsWith('.html')) app = p.withoutExtension(app);

    var buildArgs = new BazelifyBuildArguments._(
        bazelExecutable: commonArgs.bazelExecutable,
        pubPackageDir: commonArgs.pubPackageDir,
        outputDir: argResults['output-dir'],
        target: app);

    await build(buildArgs);
    watch
      ..reset()
      ..stop();
  }

  Future build(BazelifyBuildArguments args) async {
    _log('Building app at ${args.target}.html...\n');
    if (p.relative(args.pubPackageDir) != '.') {
      throw new ApplicationFailedException(
          'dazel build only supports running from your top level package '
          'directory.',
          1);
    }
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
    print('');

    var outputDir = new Directory(args.outputDir);
    if (await outputDir.exists()) {
      _log('Deleting old `${args.outputDir}` dir.');
      await outputDir.delete(recursive: true);
    }

    var file = new File("${args.target}.html");
    var entryPoint = await htmlEntryPointFromFile(file, './');
    var tarPath = 'bazel-bin/${entryPoint.dartFile}.js.tar';
    _log('Expanding tar file at `$tarPath` into `${args.outputDir}`.');
    var archive =
        new TarDecoder().decodeBytes(await new File(tarPath).readAsBytes());
    await outputDir.create();
    await Future.wait(archive.files.map((archiveFile) async {
      if (archiveFile.name.endsWith(Platform.pathSeparator)) return null;
      var outputFile = new File(p.join(args.outputDir, archiveFile.name));
      await outputFile.create(recursive: true);
      await outputFile.writeAsBytes(archiveFile.content);
    }));
    _log('Build complete! See `${args.outputDir}` dir for build output.');
  }

  void _log(String message) {
    print("${_elapsed(watch)}: $message");
  }

  String _elapsed(Stopwatch watch) {
    var elapsed = "${watch.elapsed}";

    // Strip of empty segments of the time.
    var match = _elapsedRegexp.firstMatch(elapsed);
    if (match != null) elapsed = elapsed.substring(match.end);

    // Only show 3 didgets of precision.
    return elapsed.substring(0, elapsed.length - 3);
  }
}

class BazelifyBuildArguments extends BazelifyArguments {
  /// The directory to copy the deployed output to.
  final String outputDir;

  /// The app target to build.
  final String target;

  BazelifyBuildArguments._({
    String bazelExecutable,
    String pubPackageDir,
    this.outputDir,
    this.target,
  })
      : super(bazelExecutable: bazelExecutable, pubPackageDir: pubPackageDir);
}

final _elapsedRegexp = new RegExp(r'^(0*:)*');
