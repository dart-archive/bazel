import 'dart:async';
import 'dart:io';

import 'package:dazel/src/bazelify/bazelify_config.dart';
import 'package:dazel/src/bazelify/build.dart';
import 'package:dazel/src/bazelify/pubspec.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  String loadGolden(String path) {
    return new File(p.normalize('test/goldens/$path')).readAsStringSync();
  }

  BuildFile createBuildFile(String pubspecYaml,
      {bool enableDdc: true,
      Iterable<String> excludeSources: const [],
      Map<String, BazelifyConfig> extraConfigs: const {},
      Iterable<DartWebApplication> webApps: const [],
      Iterable<DartVmBinary> binaries: const []}) {
    final pubspec = new Pubspec.parse(pubspecYaml);
    final bazelConfig = new BazelifyConfig.useDefault(pubspec,
        enableDdc: enableDdc,
        excludeSources: excludeSources,
        includeWebSources: webApps.isNotEmpty);
    final bazelConfigs = {
      pubspec.pubPackageName: bazelConfig,
    }..addAll(extraConfigs);
    return new BuildFile(bazelConfig, bazelConfigs,
        webApps: webApps, binaries: binaries);
  }

  test('should generate a simple library with no dependencies', () {
    final build = createBuildFile('name: silly_monkey');
    expect(build.toString(), loadGolden('build_file_simple_library'));
  });

  test('should generate a simple library with dependencies', () {
    final pathPubspec = new Pubspec.parse('name: path');
    final pathBazelifyConfig = new BazelifyConfig.useDefault(pathPubspec);
    final extraConfigs = {
      pathPubspec.pubPackageName: pathBazelifyConfig,
    };
    final yaml = '''
        name: silly_monkey
        dependencies:
          path: any''';
    final build = createBuildFile(yaml, extraConfigs: extraConfigs);
    expect(build.toString(), loadGolden('build_file_library_with_deps'));
  });

  test('should generate a library with a web target', () {
    final build = createBuildFile(
      'name: silly_monkey',
      webApps: [
        new DartWebApplication(
          name: 'web/index',
          package: 'silly_monkey',
          entryPoint: new HtmlEntryPoint(
              htmlFile: 'web/index.html', dartFile: 'web/main.dart'),
        )
      ],
    );
    expect(build.toString(), loadGolden('build_file_web_application'));
  });

  test('should generate a library with multiple web targets', () {
    final build = createBuildFile(
      'name: silly_monkey',
      webApps: [
        new DartWebApplication(
          name: 'web/main_web',
          package: 'silly_monkey',
          entryPoint: new HtmlEntryPoint(
              htmlFile: 'web/index.html', dartFile: 'web/main.dart'),
        ),
        new DartWebApplication(
          name: 'web/secondary_web',
          package: 'silly_monkey',
          entryPoint: new HtmlEntryPoint(
              htmlFile: 'web/secondary.html', dartFile: 'web/secondary.dart'),
        )
      ],
    );
    expect(build.toString(), loadGolden('build_file_web_application_multi'));
  });

  test('should generate a library with a binary target', () {
    final build = createBuildFile(
      'name: silly_monkey',
      binaries: [
        new DartVmBinary(
          name: 'main',
          package: 'silly_monkey',
          scriptFile: 'bin/main.dart',
        )
      ],
      excludeSources: ["lib/web_file.dart"],
      enableDdc: false,
    );
    expect(build.toString(), loadGolden('build_file_vm_binary'));
  });

  group('fromPackageDir', () {
    Future<BuildFile> loadBuildFileFromDir(String packageDir,
        {Map<String, BazelifyConfig> extraConfigs: const {},
        bool includeWebSources: false}) async {
      packageDir = p.normalize(packageDir);
      final pubspec = await Pubspec.fromPackageDir(packageDir);
      final bazelifyConfig = await BazelifyConfig.fromPackageDir(
          pubspec, packageDir,
          includeWebSources: includeWebSources);
      final bazelifyConfigs = {
        pubspec.pubPackageName: bazelifyConfig,
      }..addAll(extraConfigs);
      return BuildFile.fromPackageDir(packageDir, pubspec, bazelifyConfigs);
    }

    test('should generate a simple library with no dependencies', () async {
      final build = await loadBuildFileFromDir('test/projects/simple');
      expect(build.toString(), loadGolden('build_file_simple_library'));
    });

    test('should generate a simple library with dependencies', () async {
      final pathPubspec = new Pubspec.parse('name: path');
      final pathBazelifyConfig = new BazelifyConfig.useDefault(pathPubspec);
      var extraConfigs = {
        pathPubspec.pubPackageName: pathBazelifyConfig,
      };
      final build = await loadBuildFileFromDir('test/projects/simple_with_deps',
          extraConfigs: extraConfigs);
      expect(build.toString(), loadGolden('build_file_library_with_deps'));
    });

    test('should generate a library with a web target', () async {
      final build = await loadBuildFileFromDir('test/projects/web_application',
          includeWebSources: true);
      expect(build.toString(), loadGolden('build_file_web_application'));
    });

    test('should generate a library with a binary target', () async {
      final build = await loadBuildFileFromDir('test/projects/vm_binary');
      expect(build.toString(), loadGolden('build_file_vm_binary'));
    });

    test('should generate a library for each target', () async {
      final build =
          await loadBuildFileFromDir('test/projects/multiple_targets');
      expect(build.toString(), loadGolden('build_file_multiple_targets'));
    });

    test('should generate a dart_codegen_binary for builders', () async {
      final build = await loadBuildFileFromDir('test/projects/codegen_author');
      expect(build.toString(), loadGolden('build_file_codegen_author'));
    });

    test('should generate a codegen target for libraries', () async {
      final codegenAuthorPath = 'test/projects/codegen_author';
      final codegenAuthorPubspec =
          await Pubspec.fromPackageDir(codegenAuthorPath);
      final codegenAuthorConfig = await BazelifyConfig.fromPackageDir(
          codegenAuthorPubspec, codegenAuthorPath);
      final extraConfigs = {'codegen_author': codegenAuthorConfig};
      final build = await loadBuildFileFromDir('test/projects/codegen_consumer',
          extraConfigs: extraConfigs);
      expect(build.toString(), loadGolden('build_file_codegen_consumer'));
    });
  });
}
