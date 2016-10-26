import 'dart:async';
import 'dart:io';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:path/path.dart' as p;

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
      var relativeFilePath = p.relative(file.path,
          from: p.normalize(p.join(searchDir, '../')));
      var relativeSrcPath = p.join(p.dirname(relativeFilePath), src);
      yield new HtmlEntryPoint(
          htmlFile: relativeFilePath,
          dartFile: relativeSrcPath);
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

  static const _rulesSource = '@io_bazel_rules_dart//dart/build_rules';
  static const _coreBzl = '$_rulesSource:core.bzl';
  static const _devBzl = '$_rulesSource:dev_server.bzl';
  static const _ddcBzl = '$_rulesSource:ddc.bzl';
  static const _webBzl = '$_rulesSource:web.bzl';
  static const _vmBzl = '$_rulesSource:vm.bzl';

  /// Dependencies shared across targets in the BUILD file.
  final List<String> deps;

  /// Dart libraries.
  final List<DartLibrary> libraries;

  /// Dart VM binaries.
  final List<DartVmBinary> binaries;

  /// Dart web applications.
  final List<DartWebApplication> webApplications;

  /// Resolve and return new [BuildFile] by looking at [path].
  ///
  /// The general rule of thumb is:
  /// - Every package generates _exactly one_ dart_library
  /// - Some packages generate 1 or more dart_vm_binary or dart_web_application
  static Future<BuildFile> fromPackageDir(String path) async {
    final pubspec = await Pubspec.fromPackageDir(path);
    final binDir = new Directory(p.join(path, 'bin'));
    final webDir = new Directory(p.join(path, 'web'));
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
      binaries: binaries,
      libraries: [
        new DartLibrary(
          name: pubspec.pubPackageName,
          package: pubspec.pubPackageName,
        ),
      ],
      webApps: webApps,
      deps: pubPackagesToBazelTargets(pubspec.dependencies),
    );
  }

  /// Creates a new [BuildFile].
  BuildFile({
    Iterable<DartVmBinary> binaries: const [],
    Iterable<DartLibrary> libraries: const [],
    Iterable<DartWebApplication> webApps: const [],
    Iterable<String> deps: const [],
  })
      : this.deps = new List<String>.unmodifiable(deps),
        this.binaries = new List<DartVmBinary>.unmodifiable(binaries),
        this.libraries = new List<DartLibrary>.unmodifiable(libraries),
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
      buffer.writeln('load("$_ddcBzl", "dart_ddc_bundle")');
      buffer.writeln('load("$_devBzl", "dev_server")');
      buffer.writeln('load("$_webBzl", "dart_web_application")');
      buffer.writeln();
    }
    if (binaries.isNotEmpty) {
      buffer.writeln('# Bazelify: ${binaries.length} binaries.');
      buffer.writeln('load("$_vmBzl", "dart_vm_binary")');
      buffer.writeln();
    }

    // Visibility.
    buffer.writeln('package(default_visibility = ["//visibility:public"])\n');

    // Dependencies.
    if (deps.isEmpty) {
      buffer.writeln("# You don't have any dependencies, yet.");
      buffer.writeln(
          '# Bazelify will update this as you change your pubspec.yaml.');
      buffer.writeln('_PUB_DEPS = []\n');
    } else {
      buffer.writeln('_PUB_DEPS = [');
      deps.map/*<String>*/((d) => '    "$d",').forEach(buffer.writeln);
      buffer.writeln(']\n');
    }

    // Now, define some build rules.
    libraries
        .map/*<String>*/(
            (r) => r.toRule(includeWeb: webApplications.isNotEmpty))
        .forEach(buffer.writeln);
    webApplications
        .map/*<String>*/((r) => r.toRule(includeLibraries: libraries))
        .forEach(buffer.writeln);
    binaries
        .map/*<String>*/((r) => r.toRule(includeLibraries: libraries))
        .forEach(buffer.writeln);

    return buffer.toString();
  }
}

/// Returns a literal list of dependencies shared across targets.
///
/// For bazelify, it is architecturally simpler to generate something like:
///     ```BUILD
///     _GENERATED_PUB_DEPS = [
///         "@dep_1//:dep_1",
///         "@dep_2//:dep_2",
///         "@dep_3//:dep_3",
///     ]
///
///     dart_library(
///         name = "%package_lib",
///         srcs = glob(["lib/**"]),
///         deps = _GENERATED_PUB_DEPS,
///     )
///
///     dart_web_application(
///         name = "%package",
///         srcs = glob(["web/**"]),
///         script_file = "web/main.dart",
///         deps = _GENERATED_PUB_DEPS + [":%package_lib"],
///     )
///     ```
///
/// Makes the assumption that `package:foo` is always `@foo//:foo`.
Iterable<String> pubPackagesToBazelTargets(Iterable<String> packages) {
  return (packages.map/*<String>*/((p) => '@$p//:$p').toList()..sort()).toSet();
}

/// A Dart BUILD rule in [BuildFile].
abstract class DartBuildRule {
  /// Name of the target.
  String get name;

  /// Originating package.
  String get package;

  /// Convert to a dart_rule(...) string.
  String toRule();
}

/// A `dart_library` definition.
class DartLibrary implements DartBuildRule {
  @override
  final String name;

  @override
  final String package;

  /// Create a new `dart_library` named [name].
  const DartLibrary({this.name, this.package});

  @override
  String toRule({bool includeWeb: false}) =>
      '# Generated automatically for package:$package\n'
      'dart_library(\n'
      '    name = "$name",\n'
      '    srcs = ${includeWeb ? 'glob(["lib/**", "web/**"])' : 'glob(["lib/**"])'},\n'
      '    deps = _PUB_DEPS,\n'
      '    pub_pkg_name = "$name",\n'
      ')';
}

/// A `dart_vm_binary` definition.
class DartVmBinary implements DartBuildRule {
  @override
  final String name;

  @override
  final String package;

  /// A file with a `main` function to execute as the entry-point.
  final String scriptFile;

  /// Create a new `dart_vm_Binary` named [name] executing [scriptFile].
  const DartVmBinary({this.name, this.package, this.scriptFile});

  @override
  String toRule({Iterable<DartLibrary> includeLibraries: const []}) {
    String buffer =
        '# Generated automatically for package:$package|$scriptFile\n'
        'dart_vm_binary(\n'
        '    name = "$name",\n'
        '    srcs = glob(["bin/**"]),\n'
        '    script_file = "$scriptFile",\n'
        '    deps = _PUB_DEPS';
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
  final String name;

  @override
  final String package;

  /// An html application entry point.
  final HtmlEntryPoint entryPoint;

  /// Helper which returns [entryPoint.htmlFile].
  String get htmlFile => entryPoint.htmlFile;

  /// Helper which returns [entryPoint.dartFile].
  String get scriptFile => entryPoint.dartFile;

  /// Create a new `dart_web_application` named [name] executing [entryPoint].
  const DartWebApplication({this.name, this.package, this.entryPoint});

  @override
  String toRule({Iterable<DartLibrary> includeLibraries: const []}) {
    String buffer =
        '# Generated automatically for package:$package|$scriptFile\n'
        'dart_web_application(\n'
        '    name = "$name",\n'
        '    srcs = glob(["web/**"]),\n'
        '    script_file = "$scriptFile",\n'
        '    deps = _PUB_DEPS';
    if (includeLibraries.isEmpty) {
      buffer = '$buffer,\n)';
    } else {
      buffer += ' + [\n' +
          includeLibraries
              .map/*<String>*/((l) => '        ":${l.name}",\n')
              .join() +
          '    ],\n)';
    }
    buffer += '\ndev_server(\n'
        '    name = "${name}_dartium_serve",\n'
        '    deps = _PUB_DEPS + [\n' +
        includeLibraries.map((l) => '        ":${l.name}",\n').join() +
        '    ],\n'
        '    data = glob(["web/**"]),\n'
        ')';
    buffer += '\ndart_ddc_bundle(\n'
        '    name = "${name}_ddc_bundle",\n'
        '    entry_library = "$scriptFile",\n'
        '    entry_module = ":$package",\n'
        '    input_html = "$htmlFile",\n'
        '    output_dir = "web",\n'
        ')';
    buffer += '\ndev_server(\n'
        '    name = "${name}_ddc_serve",\n'
        '    data = [":${name}_ddc_bundle"],\n'
        '    script_args = [\n'
        '        "--package-spec=${name}_ddc_bundle.packages",\n'
        '        "--uri-substitution=$htmlFile:web/${name}_ddc_bundle.html",\n'
        '    ],\n'
        ')';
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
