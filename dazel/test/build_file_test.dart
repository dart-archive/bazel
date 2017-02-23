import 'dart:async';
import 'dart:io';

import 'package:dazel/src/bazelify/build.dart';
import 'package:dazel/src/bazelify/common.dart';
import 'package:dazel/src/bazelify/pubspec.dart';
import 'package:dazel/src/config/build_config.dart';
import 'package:dazel/src/config/config_set.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  String loadGolden(String path) {
    return new File(p.normalize('test/goldens/$path')).readAsStringSync();
  }

  BuildFile createBuildFile(String pubspecYaml,
      {bool enableDdc: true,
      Iterable<String> excludeSources: const [],
      Map<String, BuildConfig> extraConfigs: const {},
      Iterable<DartWebApplication> webApps: const [],
      Iterable<DartVmBinary> binaries: const []}) {
    final pubspec = new Pubspec.parse(pubspecYaml);
    final buildConfig = new BuildConfig.useDefault(pubspec,
        enableDdc: enableDdc,
        excludeSources: excludeSources,
        includeWebSources: webApps.isNotEmpty);
    final buildConfigs = new BuildConfigSet(buildConfig, extraConfigs);
    return new BuildFile(buildConfig, buildConfigs,
        webApps: webApps, binaries: binaries);
  }

  test('should generate a simple library with no dependencies', () {
    final build = createBuildFile('name: silly_monkey');
    expect(build.toString(), loadGolden('build_file_simple_library'));
  });

  test('should generate a simple library with dependencies', () {
    final pathPubspec = new Pubspec.parse('name: path');
    final pathBuildConfig = new BuildConfig.useDefault(pathPubspec);
    final extraConfigs = {
      pathPubspec.pubPackageName: pathBuildConfig,
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
          name: targetForAppPath('web/index.html'),
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
          name: targetForAppPath('web/main_web.html'),
          package: 'silly_monkey',
          entryPoint: new HtmlEntryPoint(
              htmlFile: 'web/index.html', dartFile: 'web/main.dart'),
        ),
        new DartWebApplication(
          name: targetForAppPath('web/secondary_web.html'),
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
        {Map<String, BuildConfig> extraConfigs: const {},
        bool includeWebSources: false}) async {
      packageDir = p.normalize(packageDir);
      final pubspec = await Pubspec.fromPackageDir(packageDir);
      final buildConfig = await BuildConfig.fromPackageDir(pubspec, packageDir,
          includeWebSources: includeWebSources);
      var allConfigs = {pubspec.pubPackageName: buildConfig}
        ..addAll(extraConfigs);
      final buildConfigs = new BuildConfigSet(buildConfig, allConfigs);
      return BuildFile.fromPackageDir(packageDir, pubspec, buildConfigs);
    }

    test('should generate a simple library with no dependencies', () async {
      final build = await loadBuildFileFromDir('test/projects/simple');
      expect(build.toString(), loadGolden('build_file_simple_library'));
    });

    test('should generate a simple library with dependencies', () async {
      final pathPubspec = new Pubspec.parse('name: path');
      final pathBuildConfig = new BuildConfig.useDefault(pathPubspec);
      var extraConfigs = {
        pathPubspec.pubPackageName: pathBuildConfig,
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
      final codegenAuthorConfig = await BuildConfig.fromPackageDir(
          codegenAuthorPubspec, codegenAuthorPath);
      final extraConfigs = {'codegen_author': codegenAuthorConfig};
      final build = await loadBuildFileFromDir('test/projects/codegen_consumer',
          extraConfigs: extraConfigs);
      expect(build.toString(), loadGolden('build_file_codegen_consumer'));
    });
  });
}
