// Copyright (c) 2017, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/src/generated/engine.dart' show AnalysisContext;
import 'package:analyzer/src/generated/source.dart' show SourceKind;
import 'package:build/build.dart'
    show Resolvers, Resolver, ReleasableResolver, BuildStep, AssetId;

import '../assets/path_translation.dart';
import 'analysis_context.dart';
import 'arg_parser.dart';
import 'build_asset_uri_resolver.dart';

/// A [Resolvers] which builds a single [AnalysisContext] backed by summaries
/// and shares it across [AnalysisResolver] instances.
///
/// For each call to [get] the [AssetId]s will be read and made available to the
/// analysisContext.
class SummaryResolvers implements Resolvers {
  final BuildAssetUriResolver _assetResolver;
  final AnalysisContext _context;
  final String _sourcesFile;
  final String _packagePath;
  final Map<String, String> _packageMap;
  final _priming = new Completer();
  bool _startedPriming = false;

  factory SummaryResolvers(
      SummaryOptions options, Map<String, String> packageMap) {
    var assetResolver = new BuildAssetUriResolver();
    return new SummaryResolvers._(
        assetResolver,
        summaryAnalysisContext(options, [assetResolver]),
        options.sourcesFile,
        options.packagePath,
        packageMap);
  }

  SummaryResolvers._(this._assetResolver, this._context, this._sourcesFile,
      this._packagePath, this._packageMap);

  @override
  Future<ReleasableResolver> get(BuildStep buildStep) async {
    await _primeWithSources(buildStep.readAsString);
    var entryPoints = [buildStep.inputId];
    await _assetResolver.addAssets(entryPoints, buildStep.readAsString);
    return new AnalysisResolver(_context, entryPoints);
  }

  Future<Null> _primeWithSources(ReadAsset readAsset) async {
    if (!_startedPriming) {
      _startedPriming = true;
      var sourceFiles = await new File(_sourcesFile).readAsLines();
      var assets = findAssetIds(sourceFiles, _packagePath, _packageMap)
          .map((asset) => new AssetId(asset.package, asset.path))
          .toList();
      await _assetResolver.addAssets(assets, readAsset);
      _priming.complete();
    } else {
      await _priming.future;
    }
  }
}

/// a [Resolver] backed by an [AnalysisContext].
class AnalysisResolver implements ReleasableResolver {
  final AnalysisContext _analysisContext;
  final List<AssetId> _assetIds;

  AnalysisResolver(this._analysisContext, this._assetIds);

  @override
  void release() => _analysisContext.dispose();

  @override
  bool isLibrary(AssetId assetId) {
    var uri = assetUri(assetId);
    var source = _analysisContext.sourceFactory.forUri2(uri);
    return source != null &&
        _analysisContext.computeKindOf(source) == SourceKind.LIBRARY;
  }

  @override
  LibraryElement getLibrary(AssetId assetId) {
    var uri = assetUri(assetId);
    var source = _analysisContext.sourceFactory.forUri2(uri);
    if (source == null) throw 'missing source for $uri';
    var kind = _analysisContext.computeKindOf(source);
    if (kind != SourceKind.LIBRARY) return null;
    var library = _analysisContext.computeLibraryElement(source);
    if (library == null) throw 'Could not resolve $assetId';
    return library;
  }

  @override
  List<LibraryElement> get libraries {
    var allLibraries = new Set<LibraryElement>();
    var uncheckedLibraries = new Queue<LibraryElement>();
    uncheckedLibraries.addAll(_assetIds.map(getLibrary));
    while (uncheckedLibraries.isNotEmpty) {
      var library = uncheckedLibraries.removeFirst();
      allLibraries.add(library);
      uncheckedLibraries.addAll(library.importedLibraries
          .where((library) => !allLibraries.contains(library)));
    }
    return allLibraries.toList();
  }

  @override
  LibraryElement getLibraryByName(String name) =>
      libraries.firstWhere((library) => library.name == name, orElse: null);
}
