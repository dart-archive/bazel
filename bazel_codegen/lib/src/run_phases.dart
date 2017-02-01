// Copyright (c) 2017, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'dart:async';
import 'dart:io';

import 'package:bazel_worker/bazel_worker.dart';
import 'package:build/build.dart';
import 'package:build_barback/build_barback.dart';
import 'package:path/path.dart' as p;

import '../bazel_codegen.dart';
import 'arg_parser.dart';
import 'assets/asset_filter.dart';
import 'assets/asset_reader.dart';
import 'assets/asset_writer.dart';
import 'errors.dart';
import 'logging.dart';
import 'summaries/summaries.dart';
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

  var options = _parseOptions(args);

  try {
    logger = await _runBuilders(builders, options, defaultContent, timings);
  } catch (e, s) {
    stderr.writeln("Dart Codegen failed with:\n$e\n$s");
    exitCode = EXIT_CODE_ERROR;
  }

  if (logger?.errorCount != 0) {
    exitCode = EXIT_CODE_ERROR;
  }
  await logger?.close();
}

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
    var options = _parseOptions(request.arguments);
    try {
      numRuns++;
      var timings = new CodegenTiming()..start();

      var bazelRelativeInputs = request.inputs
          .map((input) => _bazelRelativePath(input.path, options.rootDirs));

      logHandle = await _runBuilders(builders, options, defaultContent, timings,
          isWorker: true, validInputs: new Set()..addAll(bazelRelativeInputs));
      var logger = logHandle.logger;
      logger.info(
          'Completed in worker mode, this worker has ran $numRuns builds');
      await logHandle.close();
      var message = _loggerMessage(logHandle, options.logPath);

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

/// Runs [builders] to generate files using [options].
///
/// When there are multiple builders, the outputs of each are assumed to be
/// primary inputs to the next builder sequentially.
///
/// The [timings] instance must already be started.
Future<IOSinkLogHandle> _runBuilders(List<BuilderFactory> builders,
    Options options, Map<String, String> defaultContent, CodegenTiming timings,
    {bool isWorker: false, Set<String> validInputs}) async {
  assert(timings.isRunning);

  final srcPaths = await timings.trackOperation('Collecting input srcs', () {
    return new File(options.srcsPath).readAsLines();
  });
  if (srcPaths.isEmpty) {
    throw new CodegenError('No input files to process.');
  }

  final packageMap =
      await timings.trackOperation('Reading package map', () async {
    var lines = await new File(options.packageMapPath).readAsLines();
    return new Map<String, String>.fromIterable(
        lines.map((line) => line.split(':')),
        key: (l) => l[0],
        value: (l) => l[1]);
  });

  final writer = new BazelAssetWriter(options.outDir, packageMap,
      validInputs: validInputs);
  final reader = new BazelAssetReader(
      options.packagePath, options.rootDirs, packageMap,
      assetFilter: new AssetFilter(validInputs, packageMap, writer));
  final srcAssets = reader
      .findAssetIds(srcPaths)
      .where((id) => id.path.endsWith(options.inputExtension))
      .toList();
  var logHandle = new IOSinkLogHandle.toFile(options.logPath,
      printLevel: options.logLevel, printToStdErr: !options.isWorker);
  var logger = logHandle.logger;

  var allWrittenAssets = new Set<AssetId>();

  var inputSrcs = new Set<AssetId>()..addAll(srcAssets);
  Resolvers resolvers;
  List<String> builderArgs;
  if (options.useSummaries) {
    var summaryOptions = new SummaryOptions.fromArgs(options.additionalArgs);
    resolvers = new SummaryResolvers(summaryOptions, packageMap);
    builderArgs = summaryOptions.additionalArgs;
  } else {
    resolvers = const BarbackResolvers();
    builderArgs = options.additionalArgs;
  }
  for (var builder in builders.map((f) => f(builderArgs))) {
    try {
      await runZoned(() async {
        if (inputSrcs.isNotEmpty) {
          await timings.trackOperation(
              'Generating files: $builder',
              () => runBuilder(builder, inputSrcs, reader, writer, resolvers,
                  logger: logger));
        }
      }, zoneSpecification:
          new ZoneSpecification(print: (self, parent, zone, message) {
        if (isWorker) {
          logger.info(message);
        } else {
          parent.print(zone, message);
        }
      }));
    } catch (e, s) {
      logger.severe(
          'Caught error during code generation step '
          '$builder on ${options.packagePath}',
          e,
          s);
    }

    // Set outputs as inputs into the next builder
    inputSrcs
      ..clear()
      ..addAll(writer.assetsWritten);
    validInputs?.addAll(writer.assetsWritten
        .map((id) => p.join(packageMap[id.package], id.path)));

    // Track and clear written assets.
    allWrittenAssets.addAll(writer.assetsWritten);
    writer.assetsWritten.clear();
  }

  await timings.trackOperation('Checking outputs and writing defaults',
      () async {
    var writes = <Future>[];
    // Check all expected outputs were written or create w/provided default.
    for (var assetId in srcAssets) {
      for (var extension in options.outputExtensions) {
        var expectedAssetId = new AssetId(
            assetId.package,
            assetId.path.substring(
                    0, assetId.path.length - options.inputExtension.length) +
                extension);
        if (allWrittenAssets.contains(expectedAssetId)) continue;

        if (defaultContent.containsKey(extension)) {
          writes.add(
              writer.writeAsString(expectedAssetId, defaultContent[extension]));
        } else {
          logger.warning('Missing expected output $expectedAssetId');
        }
      }
    }
    await Future.wait(writes);
  });

  timings
    ..stop()
    ..writeLogSummary(logger);

  logger.info('Read ${reader.numAssetsReadFromDisk} files from disk');

  return logHandle;
}

/// Parse [Options] from [args].
Options _parseOptions(List<String> args) {
  var options = new Options.parse(args);
  if (options.help) {
    options.printUsage();
    return null;
  }
  return options;
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
