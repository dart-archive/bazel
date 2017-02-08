// Copyright (c) 2017, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

main() {
  group('e2e test', () {
    /// This is bad and we should feel bad
    test('dazel init', () {
      expectSuccess(Process.runSync('pub', ['run', 'dazel', 'init']));

      bazel(['version']);
      bazel(['clean']);
    });

    test('bazel run', () {
      var result = bazel(['run', ':get_cwd']);
      expect(result.stderr, contains('Running command line: '),
          reason: 'Error: ${result.stderr}');
    });

    test('dazel build', () {
      var deployDirname = 'ng2_deploy';
      var result = Process.runSync('pub',
          ['run', 'dazel', 'build', '-o', deployDirname, 'web/angular.html']);
      expectSuccess(result);
      var deployDir = new Directory(deployDirname);
      expect(deployDir.existsSync(), isTrue);
      void expectExists(Iterable<String> filePathParts) {
        var path = p.joinAll([deployDirname]..addAll(filePathParts));
        expect(new File(path).existsSync(), isTrue);
      }
      expectExists(['web', 'angular_main.dart.js']);
      expectExists(['web', 'packages/angular2/angular2.dart']);
      deployDir.deleteSync(recursive: true);
    });
  });
}

expectSuccess(ProcessResult result) {
  expect(result.exitCode, 0, reason: 'ERROR: ${result.stderr}');
  print(result.stdout);
}

ProcessResult bazel(List<String> args) {
  var command = args.removeAt(0);
  var result =
      Process.runSync('bazel', [command, '--noshow_progress']..addAll(args));
  expectSuccess(result);
  return result;
}
