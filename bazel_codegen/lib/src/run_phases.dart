// Copyright (c) 2017, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'dart:async';
import 'dart:io';

import 'package:bazel_worker/bazel_worker.dart';
import 'package:path/path.dart' as p;

import '../_bazel_codegen.dart';
import 'args/build_args.dart';
import 'errors.dart';
import 'logging.dart';
import 'run_builders.dart';
import 'timing.dart';

/// Runs builds as a worker.
Future generateAsWorker(
    List<BuilderFactory> builders, Map<String, String> defaultContent) {
  return new _CodegenWorker(builders, defaultContent).run();
}

/// Runs in single build mode (not as a worker).
Future generateSingleBuild(List<BuilderFactory> builders, List<String> args,
    Map<String, String> defaultContent) async {
  var timings = new CodegenTiming()..start();
  IOSinkLogHandle logger;

  var buildArgs = _parseArgs(args);

  try {
    logger = await _runBuilders(builders, buildArgs, defaultContent, timings);
  } catch (e, s) {
    stderr.writeln("Dart Codegen failed with:\n$e\n$s");
    exitCode = EXIT_CODE_ERROR;
  }

  if (logger?.errorCount != 0) {
    exitCode = EXIT_CODE_ERROR;
  }
  await logger?.close();
}

Future<Map<String, String>> _packageMap(
        BuildArgs buildArgs, CodegenTiming timings) async =>
    timings.trackOperation('Reading package map', () async {
      var lines = await new File(buildArgs.packageMapPath).readAsLines();
      return new Map<String, String>.fromIterable(
          lines.map((line) => line.split(':')),
          key: (l) => l[0],
          value: (l) => l[1]);
    });

String _bazelRelativePath(String inputPath, Iterable<String> outputDirs) {
  for (var outputDir in outputDirs) {
    if (inputPath.startsWith(outputDir)) {
      return p.relative(inputPath, from: outputDir);
    }
  }
  return inputPath;
}

/// Persistent worker loop implementation.
class _CodegenWorker extends AsyncWorkerLoop {
  final Map<String, String> defaultContent;
  final List<BuilderFactory> builders;
  int numRuns = 0;

  _CodegenWorker(this.builders, this.defaultContent);

  @override
  Future<WorkResponse> performRequest(WorkRequest request) async {
    IOSinkLogHandle logHandle;
    var buildArgs = _parseArgs(request.arguments);
    try {
      numRuns++;
      var timings = new CodegenTiming()..start();

      var bazelRelativeInputs = request.inputs
          .map((input) => _bazelRelativePath(input.path, buildArgs.rootDirs));

      logHandle = await _runBuilders(
          builders, buildArgs, defaultContent, timings,
          isWorker: true, validInputs: new Set()..addAll(bazelRelativeInputs));
      var logger = logHandle.logger;
      logger.info(
          'Completed in worker mode, this worker has ran $numRuns builds');
      await logHandle.close();
      var message = _loggerMessage(logHandle, buildArgs.logPath);

      var response = new WorkResponse()
        ..exitCode = logHandle.errorCount == 0 ? EXIT_CODE_OK : EXIT_CODE_ERROR;
      if (message.isNotEmpty) response.output = message;
      return response;
    } catch (e, s) {
      await logHandle?.close();
      return new WorkResponse()
        ..exitCode = EXIT_CODE_ERROR
        ..output = "Dart Codegen worker failed with:\n$e\n$s";
    }
  }
}

/// Sets up resources and runs [builders] then fills in default content.
///
/// When there are multiple builders, the outputs of each are assumed to be
/// primary inputs to the next builder sequentially.
///
/// The [timings] instance must already be started.
Future<IOSinkLogHandle> _runBuilders(
    List<BuilderFactory> builders,
    BuildArgs buildArgs,
    Map<String, String> defaultContent,
    CodegenTiming timings,
    {bool isWorker: false,
    Set<String> validInputs}) async {
  final srcPaths = await timings.trackOperation('Collecting input srcs', () {
    return new File(buildArgs.srcsPath).readAsLines();
  });
  if (srcPaths.isEmpty) {
    throw new CodegenError('No input files to process.');
  }
  final packageMap = await _packageMap(buildArgs, timings);
  return runBuilders(
      builders, buildArgs, defaultContent, srcPaths, packageMap, timings,
      isWorker: isWorker, validInputs: validInputs);
}

/// Parse [BuildArgs] from [args].
BuildArgs _parseArgs(List<String> args) {
  var buildArgs = new BuildArgs.parse(args);
  if (buildArgs.help) {
    buildArgs.printUsage();
    return null;
  }
  return buildArgs;
}

/// Builds a message about warnings/errors given a [IOSinkLogHandle].
String _loggerMessage(IOSinkLogHandle logger, String logPath) {
  if (logger.printedMessages.isNotEmpty) {
    return '\nCompleted with ${logger.errorCount} error(s) and '
        '${logger.warningCount} warning(s):\n\n'
        '${logger.printedMessages.join('\n')}\n\n'
        'See $logPath for additional details if this was a local build, or '
        'enable more verbose logging using the following flag: '
        '`--define=DART_CODEGEN_LOG_LEVEL=(fine|info|warn|error)`.';
  }
  return '';
}
