import 'dart:async';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

/// Turns a local directory into a Bazel repository.
///
/// See: https://www.bazel.io/versions/master/docs/be/workspace.html#new_local_repository
class NewLocalRepository {
  /// Name of the repository.
  final String name;

  /// Local file path.
  final String path;

  /// Dependencies (usually from [pubBazelDeps]).
  final List<String> deps;

  /// Create a `new_local_repository` macro.
  NewLocalRepository({
    @required this.name,
    @required this.path,
    Iterable<String> deps: const [],
  })
      : this.deps = new List<String>.unmodifiable(deps);

  /// Returns the contents of a suitable section of a .bzl file.
  String getRepository() {
    var buffer = new StringBuffer()
      ..writeln('native.new_local_repository(')
      ..writeln('    name = "$name",')
      ..writeln('    path = "$path",')
      ..writeln('    build_file = ".bazelify/$name.BUILD",')
      ..writeln(')');
    return buffer.toString();
  }

  /// Returns the contents of a suitable BUILD file for the repository.
  String getBuild() {
    var buffer = new StringBuffer()
      ..writeln('load("@io_bazel_rules_dart//dart/build_rules:core.bzl", "dart_library")')
      ..writeln('package(default_visibility = ["//visibility:public"])')
      ..writeln()
      ..writeln('dart_library(')
      ..writeln('    name = "$name",')
      ..writeln('    srcs = glob(["lib/**"]),')
      ..writeln('    deps = [');
    for (var dep in deps) {
      buffer.writeln('        "$dep",');
    }
    buffer..writeln('    ],')..writeln(')');
    return buffer.toString();
  }

  @override
  String toString() =>
      'NewLocalRepository {' +
      {
        'name': name,
        'path': name,
        'deps': deps,
      }.toString() +
      '}';
}

/// Generates a stream of repositories from [packages].
///
/// For the following:
///     ```
///     args:file:///.../.pub-cache/hosted/pub.dartlang.org/args-0.13.6/lib/
///     path:file:///.../.pub-cache/hosted/pub.dartlang.org/path-1.4.0/lib/
///     ```
///
/// Returns (as a stream):
///     [
///       new NewLocalRepository(
///         name: 'args',
///         path: 'file:///.../.pub-cache/hosted/pub.dart.lang.org/args-0.13.6',
///         deps: [
///           '@dep_one:dep_one',
///           '@dep_two:dep_two',
///         ],
///       ),
///     ]
Stream<NewLocalRepository> pubBazelRepos(Map<String, Uri> packages) async* {
  for (var name in packages.keys) {
    var files = packages[name].toString();
    files = files.substring(0, files.length - '/lib/'.length);
    var pubspec = Uri.parse(path.join(files, 'pubspec.yaml'));
    yield new NewLocalRepository(
      name: name,
      path: new File.fromUri(Uri.parse(files)).absolute.path,
      deps: pubBazelDeps(
        loadYaml(await new File.fromUri(pubspec).readAsString()),
      ),
    );
  }
}

/// Writes a new 'packages.bzl' file in [workspaceDir].
///
/// Returns a [Future] that completes with the file contents when done.
Future<String> generateBzl(
  String workspaceDir,
  Stream<NewLocalRepository> repositories,
) async {
  var bazelifyDir = new Directory(path.join(workspaceDir, '.bazelify'));
  if (await bazelifyDir.exists()) {
    await bazelifyDir.delete(recursive: true);
  }
  await bazelifyDir.create(recursive: true);
  var buffer = new StringBuffer();
  buffer.writeln('def bazelify():');
  await for (var repo in repositories) {
    var repoRule = repo
        .getRepository()
        .split('\n')
        .map((line) => ' ' * 4 + line)
        .join('\n');
    buffer.writeln(repoRule);
    var buildFile = path.join(workspaceDir, '.bazelify', '${repo.name}.BUILD');
    await new File(buildFile).writeAsString(repo.getBuild());
  }
  await new File(path.join(workspaceDir, 'BUILD'))
      .writeAsString(r'# Automatically generated and left blank by Bazelify');
  await new File(path.join(workspaceDir, 'packages.bzl'))
      .writeAsString(buffer.toString());
  return buffer.toString();
}

/// Generate a list of dependencies for a Bazel library from [pubspecContents].
///
/// For the following input:
///     ```yaml
///     dependencies:
///       args:
///       path:
///     ```
///
/// Returns:
///     [
///       '@args:args',
///       '@path:path',
///     ]
Iterable<String> pubBazelDeps(Map pubspecContents) {
  final dependencies = pubspecContents['dependencies'] ?? const {};
  return (dependencies as Map).keys.map((d) => '@$d//:$d');
}
