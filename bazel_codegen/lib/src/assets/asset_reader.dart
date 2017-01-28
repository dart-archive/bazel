// Copyright (c) 2017, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'dart:async';
import 'dart:convert';

import 'package:build/build.dart';
import 'package:path/path.dart' as p;

import '../errors.dart';
import 'asset_filter.dart';
import 'file_system.dart';
import 'path_translation.dart' as path_translation;

class BazelAssetReader implements AssetReader {
  /// The path to the package we are currently processing.
  final String packagePath;

  final _assetCache = <AssetId, String>{};

  /// The bazel specific file system.
  ///
  /// Responsible for knowing where bazel stores source and generated files on
  /// disk.
  final BazelFileSystem _fileSystem;

  /// A filter for which assets are allowed to be read.
  final AssetFilter _assetFilter;

  /// Maps package names to path in the bazel file system.
  final Map<String, String> _packageMap;

  int numAssetsReadFromDisk = 0;

  BazelAssetReader._(
      this.packagePath, Iterable<String> rootDirs, this._packageMap,
      {AssetFilter assetFilter})
      : _fileSystem = new BazelFileSystem('.', rootDirs),
        _assetFilter = assetFilter;

  factory BazelAssetReader(String packagePath, Iterable<String> rootDirs,
      Map<String, String> packageMap,
      {AssetFilter assetFilter}) {
    if (packagePath.endsWith('/')) {
      packagePath = packagePath.substring(0, packagePath.length - 1);
    }
    return new BazelAssetReader._(packagePath, rootDirs, packageMap,
        assetFilter: assetFilter);
  }

  BazelAssetReader.forTest(this.packagePath, this._packageMap, this._fileSystem)
      : _assetFilter = const _AllowAllAssets();

  /// Peform package name resolution and turn file paths into [AssetId]s.
  Iterable<AssetId> findAssetIds(Iterable<String> assetPaths) =>
      path_translation.findAssetIds(assetPaths, packagePath, _packageMap);

  /// Primes the cache with [assets].
  void cacheAssets(Map<AssetId, String> assets) {
    _assetCache.addAll(assets);
  }

  @override
  Future<String> readAsString(AssetId id, {Encoding encoding: UTF8}) async {
    final packagePath = _packageMap[id.package];
    if (!_assetFilter.isValid(id) || packagePath == null) {
      throw new CodegenError('Attempted to read invalid input $id.');
    }
    final filePath = p.join(packagePath, id.path);

    if (_assetCache.containsKey(id)) {
      return _assetCache[id];
    }

    numAssetsReadFromDisk++;
    final contents = _fileSystem.readAsStringSync(filePath);
    if (contents == null) {
      throw new CodegenError('Could not find $id at $filePath');
    }
    _assetCache[id] = contents;
    return contents;
  }

  @override
  Future<bool> hasInput(AssetId id) async {
    final packagePath = _packageMap[id.package];
    if (packagePath == null) return false;

    final filePath = p.join(packagePath, id.path);
    if (!_assetFilter.isValid(id)) return false;

    return _assetCache.containsKey(id) || _fileSystem.existsSync(filePath);
  }
}

class _AllowAllAssets implements AssetFilter {
  const _AllowAllAssets();
  @override
  bool isValid(AssetId id) => true;
}
