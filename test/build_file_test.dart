import 'dart:io';

import 'package:bazel/src/bazelify/build.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  BuildFile build;

  String loadGolden(String path) {
    return new File(p.normalize('test/goldens/$path')).readAsStringSync();
  }

  test('should generate a simple library with no dependencies', () {
    build = new BuildFile(
      libraries: [
        new DartLibrary(
          name: 'silly_monkey',
          package: 'silly_monkey',
        ),
      ],
    );
    expect(build.toString(), loadGolden('build_file_simple_library'));
  });

  test('should generate a simple library with dependencies', () {
    build = new BuildFile(
      libraries: [
        new DartLibrary(
          name: 'silly_monkey',
          package: 'silly_monkey',
        ),
      ],
      deps: pubPackagesToBazelTargets([
        'path',
      ]),
    );
    expect(build.toString(), loadGolden('build_file_library_with_deps'));
  });

  test('should generate a library with a web target', () {
    build = new BuildFile(
      libraries: [
        new DartLibrary(
          name: 'silly_monkey',
          package: 'silly_monkey',
        ),
      ],
      webApps: [
        new DartWebApplication(
          name: 'main_web',
          package: 'silly_monkey',
          entryPoint: new HtmlEntryPoint(
              htmlFile: 'web/index.html', dartFile: 'web/main.dart'),
        )
      ],
    );
    expect(build.toString(), loadGolden('build_file_web_application'));
  });

  test('should generate a library with a binary target', () {
    build = new BuildFile(
      libraries: [
        new DartLibrary(
          name: 'silly_monkey',
          package: 'silly_monkey',
        ),
      ],
      binaries: [
        new DartVmBinary(
          name: 'main_bin',
          package: 'silly_monkey',
          scriptFile: 'bin/main.dart',
        )
      ],
    );
    expect(build.toString(), loadGolden('build_file_vm_binary'));
  });

  group('fromPackageDir', () {
    test('should generate a simple library with no dependencies', () async {
      build = await BuildFile.fromPackageDir(
        p.normalize('test/projects/simple'),
      );
    });

    test('should generate a simple library with dependencies', () async {
      build = await BuildFile.fromPackageDir(
        p.normalize('test/projects/simple_with_deps'),
      );
    });

    test('should generate a library with a web target', () async {
      build = await BuildFile.fromPackageDir(
        p.normalize('test/projects/web_application'),
      );
    });

    test('should generate a library with a binary target', () async {
      build = await BuildFile.fromPackageDir(
        p.normalize('test/projects/vm_binary'),
      );
    });
  });
}
