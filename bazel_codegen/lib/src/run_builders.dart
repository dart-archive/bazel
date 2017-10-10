// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:analyzer/src/generated/engine.dart' show AnalysisEngine;
import 'package:build/build.dart';
import 'package:build_barback/build_barback.dart';
import 'package:path/path.dart' as p;

import '../_bazel_codegen.dart';
import 'args/build_args.dart';
import 'assets/asset_filter.dart';
import 'assets/asset_reader.dart';
import 'assets/asset_writer.dart';
import 'assets/path_translation.dart';
import 'logging.dart';
import 'summaries/summaries.dart';
import 'timing.dart';

/// Runs [builders] to generate files using [buildArgs] and fills in missing
/// outputs with default content.
///
/// When there are multiple builders, the outputs of each are assumed to be
/// primary inputs to the next builder sequentially.
///
/// The [timings] instance must already be started.
Future<IOSinkLogHandle> runBuilders(
    List<BuilderFactory> builders,
    BuildArgs buildArgs,
    Map<String, String> defaultContent,
    List<String> srcPaths,
    Map<String, String> packageMap,
    CodegenTiming timings,
    {bool isWorker: false,
    Set<String> validInputs}) async {
  assert(timings.isRunning);

  final packageName = packageMap.keys
      .firstWhere((name) => packageMap[name] == buildArgs.packagePath);

  final writer = new BazelAssetWriter(buildArgs.outDir, packageMap,
      validInputs: validInputs);
  final reader = new BazelAssetReader(
      packageName, buildArgs.rootDirs, packageMap,
      assetFilter: new AssetFilter(validInputs, packageMap, writer));
  final srcAssets = findAssetIds(srcPaths, buildArgs.packagePath, packageMap)
      .where((id) => buildArgs.buildExtensions.keys.any(id.path.endsWith))
      .toList();
  var logHandle = new IOSinkLogHandle.toFile(buildArgs.logPath,
      printLevel: buildArgs.logLevel, printToStdErr: !buildArgs.isWorker);
  var logger = logHandle.logger;

  var allWrittenAssets = new Set<AssetId>();

  var inputSrcs = new Set<AssetId>()..addAll(srcAssets);
  Resolvers resolvers;
  List<String> builderArgs;
  if (buildArgs.useSummaries) {
    var summaryOptions = new SummaryOptions.fromArgs(buildArgs.additionalArgs);
    resolvers = new SummaryResolvers(summaryOptions, packageMap);
    builderArgs = summaryOptions.additionalArgs;
  } else {
    resolvers = const BarbackResolvers();
    builderArgs = buildArgs.additionalArgs;
  }
  for (var builder in builders.map((f) => f(builderArgs))) {
    try {
      if (inputSrcs.isNotEmpty) {
        await timings.trackOperation(
            'Generating files: $builder',
            () => runBuilder(builder, inputSrcs, reader, writer, resolvers,
                logger: logger));
      }
    } catch (e, s) {
      logger.severe(
          'Caught error during code generation step '
          '$builder on ${buildArgs.packagePath}',
          e,
          s);
    }

    // Set outputs as inputs into the next builder
    inputSrcs.addAll(writer.assetsWritten);
    validInputs?.addAll(writer.assetsWritten
        .map((id) => p.join(packageMap[id.package], id.path)));

    // Track and clear written assets.
    allWrittenAssets.addAll(writer.assetsWritten);
    writer.assetsWritten.clear();
  }

  // Technically we don't always have to do this, but better safe than sorry.
  timings.trackOperation('Clearing analysis engine cache',
      () => AnalysisEngine.instance.clearCaches());

  await timings.trackOperation('Checking outputs and writing defaults',
      () async {
    var writes = <Future>[];
    // Check all expected outputs were written or create w/provided default.
    for (var assetId in srcAssets) {
      for (var inputExtension in buildArgs.buildExtensions.keys) {
        for (var extension in buildArgs.buildExtensions[inputExtension]) {
          var expectedAssetId = new AssetId(
              assetId.package,
              assetId.path.substring(
                      0, assetId.path.length - inputExtension.length) +
                  extension);
          if (allWrittenAssets.contains(expectedAssetId)) continue;

          if (defaultContent.containsKey(extension)) {
            writes.add(writer.writeAsString(
                expectedAssetId, defaultContent[extension]));
          } else {
            logger.warning('Missing expected output $expectedAssetId');
          }
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
