import 'dart:async';
import 'dart:io';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:path/path.dart' as p;

import '../config/build_config.dart';
import 'common.dart';
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

  static Stream<HtmlEntryPoint> _findHtmlEntryPoints(
      String packageDir, String searchDir) async* {
    final files = new Directory(searchDir)
        .list(recursive: true, followLinks: false)
        .where((entity) => entity is File && entity.path.endsWith('.html'));
    await for (final File file in files) {
      var entrypoint = await htmlEntryPointFromFile(file, packageDir);
      if (entrypoint != null) yield entrypoint;
    }
  }

  static Stream<DartWebApplication> _findWebApps(
      String package, String packageDir, String searchDir) {
    return _findHtmlEntryPoints(packageDir, searchDir)
        .map/*<DartWebApplication>*/((entryPoint) {
      return new DartWebApplication(
        name: targetForAppPath(entryPoint.htmlFile),
        package: package,
        entryPoint: entryPoint,
      );
    });
  }

  static const ddcServeAllName = '__ddc_serve_all';
  static const _coreBzl = '$_rulesSource:core.bzl';
  static const codegenBzl = '$_rulesSource/codegen:codegen.bzl';
  static const _rulesSource = '@io_bazel_rules_dart//dart/build_rules';
  static const _webBzl = '$_rulesSource:web.bzl';
  static const _vmBzl = '$_rulesSource:vm.bzl';

  /// The parsed `build.yaml` file.
  final BuildConfig buildConfig;

  /// All the `BuildConfig`s that are known, by package name.
  final Map<String, BuildConfig> buildConfigs;

  /// Dart libraries.
  Iterable<DartLibrary> get libraries => buildConfig.dartLibraries.values;

  /// Dart VM binaries.
  final List<DartVmBinary> binaries;

  Iterable<DartBuilderBinary> get builderBinaries =>
      buildConfig.dartBuilderBinaries.values;

  /// Dart web applications.
  final List<DartWebApplication> webApplications;

  /// Resolve and return new [BuildFile] by looking at [packageDir].
  ///
  /// The general rule of thumb is:
  /// - Every package generates one or more dart_libraries
  /// - Some packages generate 1 or more dart_vm_binary or dart_web_application
  ///
  /// A `BuildConfig` will also be created, and added to `buildConfigs`.
  static Future<BuildFile> fromPackageDir(String packageDir, Pubspec pubspec,
      Map<String, BuildConfig> buildConfigs) async {
    final buildConfig = buildConfigs[pubspec.pubPackageName];

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
          await _findWebApps(pubspec.pubPackageName, packageDir, webDir.path)
              .toList();
    }
    return new BuildFile(
      buildConfig,
      buildConfigs,
      binaries: binaries,
      webApps: webApps,
    );
  }

  /// Creates a new [BuildFile].
  BuildFile(
    this.buildConfig,
    this.buildConfigs, {
    Iterable<DartVmBinary> binaries: const [],
    Iterable<DartWebApplication> webApps: const [],
  })
      : this.binaries = new List<DartVmBinary>.unmodifiable(binaries),
        this.webApplications =
            new List<DartWebApplication>.unmodifiable(webApps);

  @override
  String toString() {
    // Preamble.
    var buffer =
        new StringBuffer('# Automatically generated by "pub run dazel".\n'
            '# DO NOT MODIFY BY HAND\n\n');

    // Import the Dart build rules as needed.
    if (libraries.isNotEmpty) {
      buffer.writeln('# Dazel: ${libraries.length} libraries.');
      buffer.writeln('load("$_coreBzl", "dart_library")');
      buffer.writeln();
    }
    if (builderBinaries.isNotEmpty) {
      buffer
        ..writeln('# Dazel: ${builderBinaries.length} codegen binaries.')
        ..writeln('load("$codegenBzl", "dart_codegen_binary")')
        ..writeln();
    }
    if (webApplications.isNotEmpty) {
      buffer.writeln('# Dazel: ${webApplications.length} web apps.');
      buffer.writeln('load(\n    "$_webBzl",\n    "dart_web_application",');
      buffer.writeln('    "dev_server",\n    "dart_ddc_bundle"\n)');
      buffer.writeln();
    }
    if (binaries.isNotEmpty) {
      buffer.writeln('# Dazel: ${binaries.length} binaries.');
      buffer.writeln('load("$_vmBzl", "dart_vm_binary")');
      buffer.writeln();
    }
    final buildersUsed =
        libraries.expand((l) => l.builders?.keys ?? const <String>[]);
    for (var builder in buildersUsed) {
      var builderDefinition = buildConfigs.values
          .expand((c) => c.dartBuilderBinaries.values)
          .firstWhere((b) => b.name == builder);
      var builderPackage = builderDefinition.package;
      buffer
        ..writeln('load(')
        ..writeln('    "//:.dazel/pub_$builderPackage.codegen.bzl",')
        ..writeln('    "$builder",')
        ..writeln(')');
    }

    // Visibility.
    buffer.writeln('package(default_visibility = ["//visibility:public"])\n');

    // Now, define some build rules.
    libraries
        .map/*<String>*/((r) => r.toRule(buildConfigs))
        .forEach(buffer.writeln);
    webApplications
        .map/*<String>*/(
            (r) => r.toRule(buildConfigs, includeLibraries: libraries))
        .forEach(buffer.writeln);

    // The general dev server target.
    if (webApplications.isNotEmpty) {
      buffer.writeln(
          new DdcDevServer(name: ddcServeAllName, webApps: webApplications)
              .toRule(buildConfigs));
    }

    binaries
        .map/*<String>*/(
            (r) => r.toRule(buildConfigs, includeLibraries: libraries))
        .forEach(buffer.writeln);

    // Note: This will throw today.
    builderBinaries
        .map/*<String>*/((r) => r.toRule(buildConfigs))
        .forEach(buffer.writeln);

    return buffer.toString();
  }
}

/// Returns a `String` representing the list of bazel targets from
/// `dependencies` using `buildConfigs` to find default target names when not
/// supplied explicitly.
String depsToBazelTargetsString(Iterable<String> dependencies,
    Map<String, BuildConfig> buildConfigs) {
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
        : buildConfigs[package].defaultDartLibrary.name;
    if (package.isEmpty) {
      targets.add(':$target');
    } else {
      targets.add('@pub_$package//:$target');
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
  String toRule(Map<String, BuildConfig> buildConfigs);
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

  /// A map from builder name to the configuration used for this target.
  final Map<String, Map<String, dynamic>> builders;

  /// Whether or not  to enable the dart development compiler.
  ///
  /// This is configured using the "platforms" option in a build.yaml file.
  final bool enableDdc;

  /// Whether or not this is the default dart library for the package.
  final bool isDefault;

  /// Sources to use as inputs for `builders`. May be `null`, in which case
  /// it should fall back on `sources`.
  final Iterable<String> generateFor;

  /// Create a new `dart_library` named [name].
  DartLibrary(
      {this.builders: const {},
      this.dependencies,
      this.enableDdc: true,
      this.excludeSources: const [],
      this.generateFor,
      this.isDefault: false,
      this.name,
      this.package,
      this.sources: const ['lib/**']});

  @override
  String toRule(Map<String, BuildConfig> buildConfigs) {
    var rule = new StringBuffer();
    var generatedTargets = <String>[];
    for (var builderName in builders.keys) {
      var targetName = '${name}_$builderName';
      generatedTargets.add(targetName);
      var generateForGlob = generateFor == null
          ? ''
          : '    generate_for = ${_sourcesToGlob(generateFor, const [])},';
      rule
        ..writeln('$builderName(')
        ..writeln('    name = "$targetName",')
        ..writeln('    srcs = ${_sourcesToGlob(sources, excludeSources)},')
        ..writeln(generateForGlob)
        ..writeln(')');
    }
    var generatedSrcs = generatedTargets.isEmpty
        ? ''
        : ' + [${generatedTargets.map((t) => '":$t"').join(', ')}]';
    var srcs = _sourcesToGlob(sources, excludeSources);
    var deps = depsToBazelTargetsString(dependencies, buildConfigs);
    rule
      ..writeln('# Generated automatically for package:$package')
      ..writeln('dart_library(')
      ..writeln('    name = "$name",')
      ..writeln('    srcs = $srcs$generatedSrcs,')
      ..writeln('    deps = $deps,')
      ..writeln('    enable_ddc = ${enableDdc ? 1 : 0},')
      ..writeln('    pub_pkg_name = "$package",')
      ..write(')');
    return '$rule';
  }

  @override
  String toString() => 'builders: $builders\n'
      'dependencies: $dependencies\n'
      'enableDdc: $enableDdc\n'
      'excludeSources: $excludeSources\n'
      'generateFor: $generateFor\n'
      'isDefault: $isDefault\n'
      'name: $name\n'
      'package: $package\n'
      'sources: $sources';
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
  String toRule(Map<String, BuildConfig> buildConfigs,
      {Iterable<DartLibrary> includeLibraries: const []}) {
    String buffer =
        '# Generated automatically for package:$package|$scriptFile\n'
        'dart_vm_binary(\n'
        '    name = "$name",\n'
        '    srcs = ${_sourcesToGlob(sources, excludeSources)},\n'
        '    script_file = "$scriptFile",\n'
        '    deps = ${depsToBazelTargetsString(dependencies, buildConfigs)}';
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

  String get ddcBundleOutputHtmlPath => '$outputDir/$ddcBundleName.html';

  String get ddcServeName => ddcServeTarget(name);

  String get htmlFile => entryPoint.htmlFile;

  // TODO: Update once we support apps outside of web.
  String get outputDir => 'web';

  String get packageSpecName => '$ddcBundleName.packages';

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
  String toRule(Map<String, BuildConfig> buildConfigs,
      {Iterable<DartLibrary> includeLibraries: const []}) {
    String buffer =
        '# Generated automatically for package:$package|$scriptFile\n'
        'dart_web_application(\n'
        '    name = "$name",\n'
        '    srcs = ${_sourcesToGlob(sources, excludeSources)},\n'
        '    script_file = "$scriptFile",\n'
        '    deps = ${depsToBazelTargetsString(dependencies, buildConfigs)}';
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
        '    output_dir = "$outputDir",\n'
        ')\n';
    buffer += new DdcDevServer(name: ddcServeName, webApps: [this])
        .toRule(buildConfigs);
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

/// A `dart_builder_binary` definition.
class DartBuilderBinary implements DartBuildRule {
  @override
  Iterable<String> get dependencies => [target];

  @override
  Iterable<String> get excludeSources => null;

  @override
  final String name;

  @override
  final String package;

  @override
  Iterable<String> get sources => null;

  /// The names of the top-level methods in [import] from args -> Builder.
  final List<String> builderFactories;

  /// The import to be used to load `clazz`.
  final String import;

  /// The input extension to treat as primary inputs to the builder.
  final String inputExtension;

  /// The expected output extensions.
  ///
  /// For each file matching `inputExtension` a matching file with each of
  /// these extensions must be output.
  final Iterable<String> outputExtensions;

  /// The name of a transformer (as it appears in a pubspec.yaml) that this
  /// builder replaces.
  ///
  /// May be null.
  final String replacesTransformer;

  /// The name of the dart_library target that contains `import`.
  final String target;

  DartBuilderBinary(
      {this.builderFactories,
      this.inputExtension,
      this.import,
      this.name,
      this.outputExtensions,
      this.package,
      this.replacesTransformer,
      this.target});

  @override
  String toRule(Map<String, BuildConfig> buildConfigs) =>
      'dart_codegen_binary(\n'
      '    name = "$name",\n'
      '    srcs = [],\n'
      '    builder_import = "$import",\n'
      '    builder_factories = [${builderFactories.map((b) => '"$b"').join(', ')}],\n'
      '    deps = [":$target"],\n'
      ')';

  @override
  String toString() => 'builderFactories: $builderFactories\n'
      'inputExtension: $inputExtension\n'
      'import: $import\n'
      'name: $name\n'
      'outputExtensions: $outputExtensions\n'
      'package: $package\n'
      'replacesTransformer: $replacesTransformer\n'
      'target: $target';

  String toCodegenRule() {
    final joinedOutputExtensions =
        outputExtensions.map((o) => '"$o"').join(', ');
    return '$name = dart_codegen_rule(\n'
        '    codegen_binary = "@pub_$package//:$name",\n'
        '    in_extension = "$inputExtension",\n'
        '    out_extensions = [$joinedOutputExtensions],\n'
        ')';
  }
}

String _sourcesToGlob(
        Iterable<String> sources, Iterable<String> excludeSources) =>
    'glob([${sources.map((s) => '"$s"').join(", ")}], '
    'exclude=[${excludeSources.map((s) => '"$s"').join(", ")}])';

/// Checks an html [file] to see if it is a dart app. If so then returns a
/// [Future<HtmlEntryPoint>] describing the app that was found, otherwise
/// returns a [Future] that completes to `null` if it was not recognized as a
/// valid dart app (generally this means it doesn't contain a dart script tag).
///
/// The [HtmlEntryPoint.htmlFile] and [HtmlEntryPoint.dartFile] will be relative
/// to [fromDir].
///
/// Throws if [file] fails to parse as html.
Future<HtmlEntryPoint> htmlEntryPointFromFile(File file, String fromDir) async {
  var document = html.parse(await file.readAsString());
  dom.Element dartScriptTag =
      document.querySelector('script[type="application/dart"]');
  if (dartScriptTag == null) return null;
  var src = dartScriptTag.attributes['src'];
  if (src == null) return null;
  if (p.isAbsolute(src)) {
    print('Only relative paths are supported for web entry point scripts, '
        'found ${dartScriptTag.outerHtml} in ${file.path} which refers to '
        'an absolute path. Entry point will be skipped.');
    return null;
  }
  // Path relative to the fromDir.
  var relativeFilePath = p.relative(file.path, from: fromDir);
  var relativeSrcPath = p.join(p.dirname(relativeFilePath), src);
  return new HtmlEntryPoint(
      htmlFile: relativeFilePath, dartFile: relativeSrcPath);
}
