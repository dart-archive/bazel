// Copyright (c) 2017, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:build/build.dart';
import 'package:path/path.dart' as path;

import '../errors.dart';

/// An [AssetWriter] tailored to bazel. Given a bazel output directory,
/// this can write general assets.
class BazelAssetWriter implements AssetWriter {
  final String _outDir;
  final Map<String, String> _packageMap;
  final Map<AssetId, String> assetsWritten = <AssetId, String>{};

  /// Workspace relative paths that we can't overwrite.
  final Set<String> _inputs;

  BazelAssetWriter(this._outDir, this._packageMap, {Set<String> validInputs})
      : _inputs = validInputs;

  @override
  Future writeAsString(Asset asset, {Encoding encoding: UTF8}) async {
    var packageDir = _packageMap[asset.id.package];
    var bazelPath = path.join(packageDir, asset.id.path);
    if (_inputs?.contains(bazelPath) == true) {
      throw new CodegenError(
          'Attempted to output ${asset.id} which was an input. Bazel does not '
          'allow overwriting of input files.');
    }

    var file = new File(path.join(_outDir, bazelPath));
    var contents = asset.stringContents;
    assetsWritten[asset.id] = contents;
    await file.create(recursive: true);
    await file.writeAsString(contents);
  }
}
