import 'dart:io';

import 'package:dazel/src/bazelify/macro.dart';
import 'package:dazel/src/bazelify/pubspec.dart';
import 'package:dazel/src/config/build_config.dart';
import 'package:dazel/src/config/config_set.dart';
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
        )
            .toString(),
        'native.new_local_repository(\n'
        '    name = "silly_monkey",\n'
        '    path = "some/path/to/.pub_cache/silly_monkey-0.0.0",\n'
        '    build_file = ".dazel/silly_monkey.BUILD",\n'
        ')\n');
  });

  test('should emit a "packages.bzl" file', () async {
    final packagesBzl = new BazelMacroFile.fromPackages(
        'silly_monkey',
        [
          'path',
        ],
        new BuildConfigSet(
            new BuildConfig.useDefault(new Pubspec.parse('name: foo')), {}),
        (package) => 'some/path/to/.pub_cache/$package-0.0.0');
    expect(
      packagesBzl.toString(),
      loadGolden('packages_bzl'),
    );
  });
}
