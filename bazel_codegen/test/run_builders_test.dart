// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import 'package:build/build.dart';
import 'package:build_barback/build_barback.dart';
import 'package:build_test/build_test.dart';
import 'package:logging/logging.dart';

import 'package:_bazel_codegen/src/run_builders.dart';
import 'package:_bazel_codegen/src/timing.dart';

import 'utils.dart';

void main() {
  group('runBuilders', () {
    InMemoryAssetWriter writer;
    InMemoryBazelAssetReader reader;
    Logger logger;
    setUp(() async {
      writer = new InMemoryAssetWriter();
      reader = new InMemoryBazelAssetReader();
      logger = new Logger('bazel_codegen_test');
    });
    test('happy case', () async {
      var builder = new CopyBuilder();
      reader.cacheStringAsset(new AssetId('foo', 'lib/source.txt'), 'source');
      await runBuilders(
        [(_) => builder],
        'foo',
        builder.buildExtensions,
        {},
        ['foo/lib/source.txt'],
        {'foo': 'foo'},
        new CodegenTiming()..start(),
        writer,
        reader,
        logger,
        const BarbackResolvers(),
        [],
      );
      expect(writer.assets.keys,
          contains(new AssetId('foo', 'lib/source.txt.copy')));
    });
  });
}
