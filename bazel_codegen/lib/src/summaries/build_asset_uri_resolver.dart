// Copyright (c) 2017, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'dart:async';

import 'package:analyzer/src/generated/engine.dart' show TimestampedData;
import 'package:analyzer/src/generated/source.dart';
import 'package:build/build.dart' show AssetId;
import 'package:path/path.dart' as p;

typedef Future<String> ReadAsset(AssetId assetId);

/// A [UriResolver] which can read build assets by reading them as strings.
///
/// Will only read each asset once. This resolver does not handle cases where
/// assets may change during a build process.
class BuildAssetUriResolver implements UriResolver {
  final _knownAssets = <Uri, Source>{};
  final _uriByAssetId = <AssetId, Uri>{};

  /// Read all [assets] with the extension '.dart' using the [read] function up
  /// front and cache them as a [Source].
  Future<Null> addAssets(Iterable<AssetId> assets, ReadAsset read) async {
    for (var asset in assets.where((asset) => asset.path.endsWith('.dart'))) {
      var uri = assetUri(asset);
      if (!_knownAssets.containsKey(uri)) {
        _knownAssets[uri] = new AssetSource(asset, await read(asset));
        _uriByAssetId[asset] = uri;
      }
    }
  }

  @override
  Source resolveAbsolute(Uri uri, [Uri actualUri]) => _knownAssets[uri];

  @override
  Uri restoreAbsolute(Source source) {
    var parts = source.fullName.split('|');
    if (parts.length != 2) return null;
    var package = parts[0].split('/').last;
    var id = new AssetId(package, parts[1]);
    return _uriByAssetId[id];
  }
}

class AssetSource implements Source {
  final AssetId _assetId;
  final String _content;

  AssetSource(this._assetId, this._content);

  @override
  TimestampedData<String> get contents => new TimestampedData(0, _content);

  @override
  String get encoding => '$_assetId';

  @override
  String get fullName => '$_assetId';

  @override
  int get hashCode => _assetId.hashCode;

  @override
  bool get isInSystemLibrary => false;

  @override
  Source get librarySource => null;

  @override
  int get modificationStamp => 0;

  @override
  String get shortName => p.basename(_assetId.path);

  @override
  Source get source => this;

  @override
  Uri get uri => assetUri(_assetId);

  @override
  UriKind get uriKind {
    if (_assetId.path.startsWith('lib/')) return UriKind.PACKAGE_URI;
    return UriKind.FILE_URI;
  }

  @override
  bool operator ==(Object object) =>
      object is AssetSource && object._assetId == _assetId;

  @override
  bool exists() => true;

  @override
  String toString() => 'AssetSource[$_assetId]';
}

Uri assetUri(AssetId assetId) => assetId.path.startsWith('lib/')
    ? new Uri(
        scheme: 'package',
        path: '${assetId.package}/${assetId.path.replaceFirst('lib/','')}')
    : new Uri(scheme: 'asset', path: '${assetId.package}/${assetId.path}');
