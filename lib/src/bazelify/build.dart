import 'dart:async';
import 'dart:io';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:path/path.dart' as p;

import 'bazelify_config.dart';
import 'pubspec.dart';

// These set of classes are specific to Bazelify and have limited use outside
// of this package, intentionally. We should pivot to use Bazel-team provided
// tools for parsing and creating BUILD files in the near future instead of
// upgrading this package for too many use cases.

/// A generator for bazel BUILD files.
class BuildFile {
  static Stream<String> _findMains(String searchDir) async* {
    final files = new Directory(searchDir)
        .list(recursive: true, followLinks: false)
        .where((entity) => entity is File && entity.path.endsWith('.dart'));
    await for (final File file in files) {
      // A really naive check for something named main. Unlikely to break for
      // typical projects, but should probably use package:analyzer in the
      // near future.
      if ((await file.readAsString()).contains('main(')) {
        yield file.path;
      }
    }
  }

  static Stream<DartVmBinary> _findBinaries(String package, String bin) {
    return _findMains(bin).map/*<DartVmBinary>*/((scriptFile) {
      return new DartVmBinary(
        name: p.basenameWithoutExtension(scriptFile),
        package: package,
        scriptFile:
            p.relative(scriptFile, from: p.normalize(p.join(bin, '../'))),
      );
    });
  }

  static Stream<HtmlEntryPoint> _findHtmlEntryPoints(String searchDir) async* {
    final files = new Directory(searchDir)
        .list(recursive: true, followLinks: false)
        .where((entity) => entity is File && entity.path.endsWith('.html'));
    await for (final File file in files) {
      var document = html.parse(await file.readAsString());
      dom.Element dartScriptTag =
          document.querySelector('script[type="application/dart"]');
      if (dartScriptTag == null) continue;
      var src = dartScriptTag.attributes['src'];
      if (src == null) continue;
      if (p.isAbsolute(src)) {
        print('Only relative paths are supported for web entry point scripts, '
            'found ${dartScriptTag.outerHtml} in ${file.path} which refers to '
            'an absolute path. Entry point will be skipped.');
        continue;
      }
      // Path relative to the package root.
      var relativeFilePath =
          p.relative(file.path, from: p.normalize(p.join(searchDir, '../')));
      var relativeSrcPath = p.join(p.dirname(relativeFilePath), src);
      yield new HtmlEntryPoint(
          htmlFile: relativeFilePath, dartFile: relativeSrcPath);
    }
  }

  static Stream<DartWebApplication> _findWebApps(String package, String web) {
    return _findHtmlEntryPoints(web).map/*<DartWebApplication>*/((entryPoint) {
      return new DartWebApplication(
        name: p.basenameWithoutExtension(entryPoint.htmlFile),
        package: package,
        entryPoint: entryPoint,
      );
    });
  }

  static const ddcServeAllName = '__ddc_serve_all';
  static const _coreBzl = '$_rulesSource:core.bzl';
  static const _rulesSource = '@io_bazel_rules_dart//dart/build_rules';
  static const _webBzl = '$_rulesSource:web.bzl';
  static const _vmBzl = '$_rulesSource:vm.bzl';

  /// The parsed `bazelify.yaml` file.
  final BazelifyConfig bazelifyConfig;

  /// All the `BazelifyConfig`s that are known, by package name.
  final Map<String, BazelifyConfig> bazelifyConfigs;

  /// Dart libraries.
  Iterable<DartLibrary> get libraries => bazelifyConfig.dartLibraries.values;

  /// Dart VM binaries.
  final List<DartVmBinary> binaries;

  /// Dart web applications.
  final List<DartWebApplication> webApplications;

  /// Resolve and return new [BuildFile] by looking at [packageDir].
  ///
  /// The general rule of thumb is:
  /// - Every package generates _exactly one_ dart_library
  /// - Some packages generate 1 or more dart_vm_binary or dart_web_application
  ///
  /// A `BazelifyConfig` will also be created, and added to `bazelifyConfigs`.
  static Future<BuildFile> fromPackageDir(String packageDir, Pubspec pubspec,
      Map<String, BazelifyConfig> bazelifyConfigs) async {
    final bazelifyConfig = bazelifyConfigs[pubspec.pubPackageName];

    final binDir = new Directory(p.join(packageDir, 'bin'));
    final webDir = new Directory(p.join(packageDir, 'web'));
    Iterable<DartVmBinary> binaries = const [];
    if (await binDir.exists()) {
      binaries =
          await _findBinaries(pubspec.pubPackageName, binDir.path).toList();
    }
    Iterable<DartWebApplication> webApps = const [];
    if (await webDir.exists()) {
      webApps =
          await _findWebApps(pubspec.pubPackageName, webDir.path).toList();
    }
    return new BuildFile(
      bazelifyConfig,
      bazelifyConfigs,
      binaries: binaries,
      webApps: webApps,
    );
  }

  /// Creates a new [BuildFile].
  BuildFile(
    this.bazelifyConfig,
    this.bazelifyConfigs, {
    Iterable<DartVmBinary> binaries: const [],
    Iterable<DartWebApplication> webApps: const [],
  })
      : this.binaries = new List<DartVmBinary>.unmodifiable(binaries),
        this.webApplications =
            new List<DartWebApplication>.unmodifiable(webApps);

  @override
  String toString() {
    // Preamble.
    var buffer = new StringBuffer(
        '# Automatically generated by "pub global run bazel:bazelify".\n'
        '# DO NOT MODIFY BY HAND\n\n');

    // Import the Dart build rules as needed.
    if (libraries.isNotEmpty) {
      buffer.writeln('# Bazelify: ${libraries.length} libraries.');
      buffer.writeln('load("$_coreBzl", "dart_library")');
      buffer.writeln();
    }
    if (webApplications.isNotEmpty) {
      buffer.writeln('# Bazelify: ${webApplications.length} web apps.');
      buffer.writeln('load(\n    "$_webBzl",\n    "dart_web_application",');
      buffer.writeln('    "dev_server",\n    "dart_ddc_bundle"\n)');
      buffer.writeln();
    }
    if (binaries.isNotEmpty) {
      buffer.writeln('# Bazelify: ${binaries.length} binaries.');
      buffer.writeln('load("$_vmBzl", "dart_vm_binary")');
      buffer.writeln();
    }

    // Visibility.
    buffer.writeln('package(default_visibility = ["//visibility:public"])\n');

    // Now, define some build rules.
    libraries
        .map/*<String>*/((r) => r.toRule(bazelifyConfigs))
        .forEach(buffer.writeln);
    webApplications
        .map/*<String>*/(
            (r) => r.toRule(bazelifyConfigs, includeLibraries: libraries))
        .forEach(buffer.writeln);

    // The general dev server target.
    if (webApplications.isNotEmpty) {
      buffer.writeln(
          new DdcDevServer(name: ddcServeAllName, webApps: webApplications)
              .toRule(bazelifyConfigs));
    }

    binaries
        .map/*<String>*/(
            (r) => r.toRule(bazelifyConfigs, includeLibraries: libraries))
        .forEach(buffer.writeln);

    return buffer.toString();
  }
}

/// Returns a `String` representing the list of bazel targets from
/// `dependencies` using `bazelifyConfigs` to find default target names when not
/// supplied explicitly.
String depsToBazelTargetsString(Iterable<String> dependencies,
    Map<String, BazelifyConfig> bazelifyConfigs) {
  var targets = new Set<String>();
  for (var dep in dependencies) {
    var parts = dep.split(':');
    if (parts.length > 2) {
      throw new ArgumentError('Invalid dependency format `$dep`, expected '
          'either one or zero colons but found ${parts.length - 1}.');
    }
    var package = parts[0];
    var target = parts.length > 1
        ? parts[1]
        : bazelifyConfigs[package].defaultDartLibrary.name;
    if (package.isEmpty) {
      targets.add(':$target');
    } else {
      targets.add('@$package//:$target');
    }
  }
  return '[${targets.map((t) => '"$t"').join(',')}]';
}

/// A Dart BUILD rule in [BuildFile].
abstract class DartBuildRule {
  /// Dependencies of this rule, in "$package:$target" format, where the
  /// target name is optional.
  Iterable<String> get dependencies;

  /// Sources to exclude from `sources`. Glob syntax is supported.
  Iterable<String> get excludeSources;

  /// Name of the target.
  String get name;

  /// Originating package.
  String get package;

  /// Sources for this rule. Glob syntax is supported.
  Iterable<String> get sources;


  /// Convert to a dart_rule(...) string.
  String toRule(Map<String, BazelifyConfig> bazelifyConfigs);
}

/// A `dart_library` definition.
class DartLibrary implements DartBuildRule {
  @override
  final Iterable<String> dependencies;

  @override
  final Iterable<String> excludeSources;

  @override
  final String name;

  @override
  final String package;

  @override
  final Iterable<String> sources;

  /// Whether or not  to enable the dart development compiler.
  ///
  /// This is configured using the "platforms" option in a bazelify.yaml file.
  final bool enableDdc;

  /// Whether or not this is the default dart library for the package.
  final bool isDefault;

  /// Create a new `dart_library` named [name].
  DartLibrary(
      {this.dependencies,
      this.enableDdc: true,
      this.excludeSources: const [],
      this.isDefault: false,
      this.name,
      this.package,
      this.sources: const ['lib/**']});

  @override
  String toRule(Map<String, BazelifyConfig> bazelifyConfigs) =>
      '# Generated automatically for package:$package\n'
      'dart_library(\n'
      '    name = "$name",\n'
      '    srcs = ${_sourcesToGlob(sources, excludeSources)},\n'
      '    deps = ${depsToBazelTargetsString(dependencies, bazelifyConfigs)},\n'
      '    enable_ddc = ${enableDdc ? 1 : 0},\n'
      '    pub_pkg_name = "$package",\n'
      ')';

  @override
  String toString() =>
      'package: $package\n'
      'name: $name\n'
      'sources: $sources\n'
      'excludeSources: $excludeSources\n'
      'dependencies: $dependencies\n'
      'isDefault: $isDefault\n'
      'enableDdc: $enableDdc';
}

/// A `dart_vm_binary` definition.
class DartVmBinary implements DartBuildRule {
  @override
  final Iterable<String> dependencies;

  @override
  final Iterable<String> excludeSources;

  @override
  final String name;

  @override
  final String package;

  @override
  final Iterable<String> sources;

  /// A file with a `main` function to execute as the entry-point.
  final String scriptFile;

  /// Create a new `dart_vm_Binary` named [name] executing [scriptFile].
  const DartVmBinary(
      {this.dependencies: const [],
      this.excludeSources: const [],
      this.name,
      this.package,
      this.scriptFile,
      this.sources: const ['bin/**']});

  @override
  String toRule(Map<String, BazelifyConfig> bazelifyConfigs,
      {Iterable<DartLibrary> includeLibraries: const []}) {
    String buffer =
        '# Generated automatically for package:$package|$scriptFile\n'
        'dart_vm_binary(\n'
        '    name = "$name",\n'
        '    srcs = ${_sourcesToGlob(sources, excludeSources)},\n'
        '    script_file = "$scriptFile",\n'
        '    deps = ${depsToBazelTargetsString(dependencies, bazelifyConfigs)}';
    if (includeLibraries.isEmpty) {
      return '$buffer,\n)';
    } else {
      return buffer +
          ' + [\n' +
          includeLibraries
              .map/*<String>*/((l) => '        ":${l.name}",\n')
              .join() +
          '    ],\n)';
    }
  }
}

/// A `dart_web_application` definition.
class DartWebApplication implements DartBuildRule {
  @override
  final Iterable<String> dependencies;

  @override
  final Iterable<String> excludeSources;

  @override
  final String name;

  @override
  final String package;

  @override
  final Iterable<String> sources;

  /// An html application entry point.
  final HtmlEntryPoint entryPoint;

  String get ddcBundleName => '${name}_ddc_bundle';

  String get ddcBundleOutputHtmlPath => 'web/$ddcBundleName.html';

  String get ddcServeName => '${name}_ddc_serve';

  String get htmlFile => entryPoint.htmlFile;

  String get packageSpecName => '${name}_ddc_bundle.packages';

  String get scriptFile => entryPoint.dartFile;

  /// Create a new `dart_web_application` named [name] executing [entryPoint].
  const DartWebApplication(
      {this.dependencies: const [],
      this.excludeSources: const [],
      this.name,
      this.package,
      this.sources: const ['web/**'],
      this.entryPoint});

  @override
  String toRule(Map<String, BazelifyConfig> bazelifyConfigs,
      {Iterable<DartLibrary> includeLibraries: const []}) {
    String buffer =
        '# Generated automatically for package:$package|$scriptFile\n'
        'dart_web_application(\n'
        '    name = "$name",\n'
        '    srcs = ${_sourcesToGlob(sources, excludeSources)},\n'
        '    script_file = "$scriptFile",\n'
        '    deps = ${depsToBazelTargetsString(dependencies, bazelifyConfigs)}';
    if (includeLibraries.isEmpty) {
      buffer = '$buffer,\n)';
    } else {
      buffer += ' + [\n' +
          includeLibraries
              .map/*<String>*/((l) => '        ":${l.name}",\n')
              .join() +
          '    ],\n)';
    }
    buffer += '\ndart_ddc_bundle(\n'
        '    name = "$ddcBundleName",\n'
        '    entry_library = "$scriptFile",\n'
        '    entry_module = ":$package",\n'
        '    input_html = "$htmlFile",\n'
        '    output_dir = "web",\n'
        ')\n';
    buffer += new DdcDevServer(name: ddcServeName, webApps: [this])
        .toRule(bazelifyConfigs);
    buffer += '\n';
    return buffer;
  }
}

/// Simple class representing an html file and its corresponding dart script.
class HtmlEntryPoint {
  final String dartFile;
  final String htmlFile;

  HtmlEntryPoint({this.dartFile, this.htmlFile}) {
    assert(dartFile != null);
    assert(htmlFile != null);
  }
}

/// A `dev_server` definition for one or more ddc web apps.
class DdcDevServer implements DartBuildRule {
  @override
  Iterable<String> get dependencies => [];

  @override
  Iterable<String> get excludeSources => null;

  @override
  final String name;

  @override
  String get package =>
      throw new UnimplementedError('DdcDevServer doesn\'t need a package');

  @override
  Iterable<String> get sources => null;

  /// one or more web applications this server serves
  final List<DartWebApplication> webApps;

  /// Create a new `dev_server` named [name] executing [webApps].
  const DdcDevServer({this.name, this.webApps});

  @override
  String toRule(_) {
    var buffer = new StringBuffer();
    if (webApps.isNotEmpty) {
      buffer.writeln('# A ddc specific dev_server target which serves '
          '${webApps.map((app) => app.name).join(', ')}');
      buffer.writeln('dev_server(\n'
          '    name = "$name",\n'
          '    data = [');
      for (var webApp in webApps) {
        buffer.writeln('        ":${webApp.ddcBundleName}",');
      }
      // Note: the package spec is the same for all targets, we just grab the
      // first one.
      buffer.writeln('    ],\n'
          '    script_args = [\n'
          '        "--package-spec='
          '${webApps.first.packageSpecName}",');
      for (var webApp in webApps) {
        buffer.writeln('        "--uri-substitution='
            '${webApp.htmlFile}:${webApp.ddcBundleOutputHtmlPath}",');
      }
      buffer.write('    ],\n'
          ')');
    }
    return buffer.toString();
  }
}

String _sourcesToGlob(
    Iterable<String> sources, Iterable<String> excludeSources) =>
    'glob([${sources.map((s) => '"$s"').join(", ")}], '
    'exclude=[${excludeSources.map((s) => '"$s"').join(", ")}])';
