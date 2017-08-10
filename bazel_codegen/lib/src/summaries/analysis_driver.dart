// Copyright (c) 2017, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'package:analyzer/src/dart/analysis/driver.dart';
import 'package:analyzer/src/dart/analysis/file_state.dart';
import 'package:analyzer/src/generated/engine.dart'
    show AnalysisEngine, AnalysisOptionsImpl;
import 'package:analyzer/src/generated/source.dart';
import 'package:analyzer/src/summary/package_bundle_reader.dart'
    show InSummaryUriResolver, SummaryDataStore;
import 'package:analyzer/file_system/physical_file_system.dart'
    show PhysicalResourceProvider;
import 'package:analyzer/src/summary/summary_sdk.dart' show SummaryBasedDartSdk;
import 'package:front_end/src/base/performace_logger.dart';
import 'package:front_end/src/byte_store/byte_store.dart';

import 'arg_parser.dart';

/// Builds an [AnalysisDriver] backed by a summary SDK and package summary
/// files.
///
/// Any code which is not covered by the summaries must be resolvable through
/// [additionalResolvers].
AnalysisDriver summaryAnalysisDriver(
    SummaryOptions options, Iterable<UriResolver> additionalResolvers) {
  AnalysisEngine.instance.processRequiredPlugins();
  var sdk = new SummaryBasedDartSdk(options.sdkSummary, true);
  var sdkResolver = new DartUriResolver(sdk);

  var summaryDataStore = new SummaryDataStore(options.summaryPaths);
  summaryDataStore.addBundle(null, sdk.bundle);
  var summaryResolver = new InSummaryUriResolver(
      PhysicalResourceProvider.INSTANCE, summaryDataStore);

  var resolvers = []
    ..addAll(additionalResolvers)
    ..add(sdkResolver)
    ..add(summaryResolver);
  var sourceFactory = new SourceFactory(resolvers);

  var analysisOptions = new AnalysisOptionsImpl()..strongMode = true;
  var logger = new PerformanceLog(null);
  var scheduler = new AnalysisDriverScheduler(logger);
  var driver = new AnalysisDriver(
      scheduler,
      logger,
      PhysicalResourceProvider.INSTANCE,
      new MemoryByteStore(),
      new FileContentOverlay(),
      null,
      sourceFactory,
      analysisOptions,
      externalSummaries: summaryDataStore);

  scheduler.start();
  return driver;
}
