// Copyright (c) 2017, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'dart:io';

import 'package:build/build.dart';
import 'package:test/test.dart';

import 'package:bazel_codegen/src/assets/asset_reader.dart';
import 'package:bazel_codegen/src/assets/file_system.dart';

void main() {
  const packagePath = 'test/package/test_package';
  const packageName = 'test.package.test_package';
  const packageMap = const {packageName: packagePath};
  final f1AssetId = new AssetId(packageName, 'lib/filename1.dart');
  final f2AssetId = new AssetId(packageName, 'lib/src/filename2.dart');
  BazelAssetReader reader;
  FakeFileSystem fileSystem;

  setUp(() {
    fileSystem = new FakeFileSystem();
    reader = new BazelAssetReader.forTest(packagePath, packageMap, fileSystem);
  });

  test('findAssetids tranlsates paths', () {
    final translatedAssets = reader.findAssetIds([
      'test/package/test_package/lib/filename1.dart',
      'test/package/test_package/lib/src/filename2.dart',
    ]);
    expect(translatedAssets, equals([f1AssetId, f2AssetId]));
  });

  test('hasInput', () async {
    final nonLoadedId = f1AssetId.changeExtension('.dne');
    fileSystem.nextExistsReturn = true;
    expect(await reader.hasInput(nonLoadedId), isTrue);
    expect(fileSystem.calls, isNotEmpty);
    expect(fileSystem.calls.single.memberName, equals(#existsSync));

    final otherUnloadedId = f1AssetId.changeExtension('.broken.link');
    fileSystem.nextExistsReturn = false;
    expect(await reader.hasInput(otherUnloadedId), isFalse);
  });

  test('readAsString', () async {
    final contents = 'Test File Contents';
    fileSystem.nextFileContents = contents;
    expect(await reader.readAsString(f1AssetId), equals(contents));
    expect(fileSystem.calls, isNotEmpty);
    expect(fileSystem.calls.single.memberName, equals(#readAsStringSync));
  });

  test('readAsBytes', () async {
    final contents = [1, 2, 3];
    fileSystem.nextFileContents = contents;
    expect(await reader.readAsBytes(f1AssetId), equals(contents));
    expect(fileSystem.calls, isNotEmpty);
    expect(fileSystem.calls.single.memberName, equals(#readAsBytesSync));
  });
}

@proxy
class FakeFileSystem implements BazelFileSystem {
  final calls = <Invocation>[];

  bool nextExistsReturn = false;
  Object nextFileContents = 'Fake File Contents';

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation);
    if (invocation.memberName == #existsSync) {
      return nextExistsReturn;
    } else if (invocation.memberName == #readAsStringSync ||
        invocation.memberName == #readAsBytesSync) {
      return nextFileContents;
    }
    return null;
  }
}

@proxy
class NullSink implements IOSink {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
