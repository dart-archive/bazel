import 'dart:io';

import 'package:bazel/src/bazelify/macro.dart';
import 'package:bazel/src/bazelify/pubspec.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  String loadGolden(String path) {
    return new File(p.normalize('test/goldens/$path')).readAsStringSync();
  }

  test('should emit a $NewLocalRepository', () {
    expect(
        new NewLocalRepository(
          name: 'silly_monkey',
          path: 'some/path/to/.pub_cache/silly_monkey-0.0.0',
          buildFile: '.bazelify/silly_monkey.BUILD',
        )
            .toString(),
        'native.new_local_repository(\n'
        '    name = "silly_monkey",\n'
        '    path = "some/path/to/.pub_cache/silly_monkey-0.0.0",\n'
        '    build_file = ".bazelify/silly_monkey.BUILD",\n'
        ')\n');
  });

  test('should emit a "packages.bzl" file', () async {
    final packagesBzl = new BazelMacroFile.fromPubspec(
      await Pubspec
          .fromPackageDir(p.normalize('test/projects/simple_with_deps')),
      (package) => 'some/path/to/.pub_cache/$package-0.0.0',
    );
    expect(
      packagesBzl.toString(),
      loadGolden('packages_bzl'),
    );
  });
}
