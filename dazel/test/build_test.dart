// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

main() {
  group('dazel build', () {
    test('hello world', () async {
      var pubspec = d.file(
          'pubspec.yaml',
          '''
          name: hello_world
          dependencies:
            path: any
          dev_dependencies:
            dazel:
              path: ${Directory.current.path}
          ''');
      var indexHtml = d.file(
          'index.html',
          '''
          <html>
            <head>
              <script type="application/dart" src="index.dart"></script>create
            </head>
          </html>
            ''');
      var indexDart = d.file(
          'index.dart',
          '''
          import 'package:path/path.dart';

          main() {
            print(join('hello', 'world'));
          }
          ''');

      await d.dir('hello_world', [
        pubspec,
        d.dir('web', [
          indexHtml,
          indexDart,
        ]),
      ]).create();

      var workingDir = p.join(d.sandbox, 'hello_world');
      var result =
          Process.runSync('pub', ['get'], workingDirectory: workingDir);
      expect(result.exitCode, 0, reason: result.stderr);

      result = Process.runSync('pub', ['run', 'dazel', 'init'],
          workingDirectory: workingDir);
      expect(result.exitCode, 0, reason: result.stderr);

      result = Process.runSync(
          'pub', ['run', 'dazel', 'build', 'web/index.html'],
          workingDirectory: workingDir);
      expect(result.exitCode, 0, reason: result.stderr);

      await d.dir('hello_world', [
        d.dir('deploy', [
          d.dir('web', [
            indexHtml,
            indexDart,
            d.file('index.dart.js', isNotEmpty),
            d.dir('packages', [
              d.dir('path', [
                d.file('path.dart', isNotEmpty),
              ]),
            ]),
          ]),
        ]),
      ]).validate();
    });
  });
}
