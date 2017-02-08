// Copyright (c) 2017, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('e2e test', () {
    setUpAll(() {
      expectSuccess(Process.runSync('pub', ['run', 'dazel', 'init']));
    });

    tearDown(() {
      bazel(['clean']);
    });

    test('bazel version', () {
      bazel(['version']);
    });

    test('bazel run', () {
      var result = bazel(['run', ':get_cwd']);
      expect(result.stderr, contains('Running command line: '),
          reason: 'Error: ${result.stderr}');
    });

    test('dazel build', () {
      var deployDirname = 'hello_world_deploy';
      var result = Process.runSync(
          'pub', [
            'run',
            'dazel',
            'build',
            '-o',
            deployDirname,
            'web/hello_world.html',
          ]);
      expectSuccess(result);
      var deployDir = new Directory(deployDirname);
      expect(deployDir.existsSync(), isTrue);
      expectExists([deployDirname, 'web', 'hello_world.dart.js']);
      expectExists([deployDirname, 'web', 'packages/path/path.dart']);
      deployDir.deleteSync(recursive: true);
    });

    test('ddc build', () {
      var result = bazel(['build', ':web__hello_world_ddc_serve']);
      expectExists([
        'bazel-bin',
        'e2e_test.js',
      ]);
      expectExists([
        'bazel-bin',
        'external',
        'pub_path',
        'path.js',
      ]);
      expectExists([
        'bazel-bin',
        'web',
        'web__hello_world_ddc_bundle.html',
      ]);
      expectExists([
        'bazel-bin',
        'web',
        'web__hello_world_ddc_bundle.js',
      ]);
    });
  });
}

void expectExists(Iterable<String> filePathParts) {
  var path = p.joinAll(filePathParts);
  expect(new File(path).existsSync(), isTrue,
      reason: 'Expected file at $path to exist, but it wasn\'t found.');
}

void expectSuccess(ProcessResult result) {
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
