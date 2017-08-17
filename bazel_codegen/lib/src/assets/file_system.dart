// Copyright (c) 2017, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:glob/glob.dart';

class BazelFileSystem {
  final String workspaceDir;
  final List<String> searchPaths;

  BazelFileSystem(this.workspaceDir, this.searchPaths) {
    if (workspaceDir == null) throw new ArgumentError();
    if (searchPaths == null) throw new ArgumentError();
  }

  //TODO; replace with async version
  bool existsSync(String path) {
    for (var searchPath in searchPaths) {
      var f = new File(p.join(workspaceDir, searchPath, path));
      if (f.existsSync()) return true;
    }
    return false;
  }

  //TODO; replace with async version
  List<int> readAsBytesSync(String path) =>
      _fileForPath(path).readAsBytesSync();

  //TODO; replace with async version
  String readAsStringSync(String path, {Encoding encoding: UTF8}) =>
      _fileForPath(path).readAsStringSync(encoding: encoding ?? UTF8);

  Iterable<String> findAssets(String packagePath, Glob glob) sync* {
    for (var searchPath in searchPaths) {
      var fullPath = p.join(workspaceDir, searchPath, packagePath);
      if (!new Directory(fullPath).existsSync()) continue;
      yield* glob
          .listSync(root: fullPath)
          .map((e) => e.path)
          .map((path) => p.relative(path, from: fullPath));
    }
  }

  File _fileForPath(String path) {
    for (var searchPath in searchPaths) {
      var f = new File(p.join(workspaceDir, searchPath, path));
      if (f.existsSync()) return f;
    }
    throw new FileSystemException('File not found', path);
  }
}
