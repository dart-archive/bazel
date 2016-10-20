// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:which/which.dart';

/// Arguments when running `bazelify`, which adds Bazel support on top of pub.
class BazelifyArguments {
  static final ArgParser _argParser = new ArgParser()
    ..addOption(
      'bazel',
      help: 'A path to the "bazel" executable. Defauls to your PATH.',
    )
    ..addOption(
      'rules-commit',
      help: 'A commit SHA on dart-lang/rules_dart to use.',
    )
    ..addOption(
      'rules-local',
      help: 'The path to a local version of rules_dart.',
    )
    ..addOption(
      'rules-tag',
      help: 'A tagged version on dart-lang/rules_dart to use.',
    )
    ..addOption(
      'pub',
      help: 'A path to the "pub" executable. Defaults to your PATH.',
    )
    ..addOption(
      'package',
      abbr: 'p',
      help: 'A directory where "pubspec.yaml" is present. Defaults to CWD.',
    );

  /// Returns the proper usage for arguments.
  static String getUsage() => _argParser.usage;

  /// A path to the 'bazel' executable.
  ///
  /// If `null` implicitly defaults to your PATH.
  final String bazelExecutable;

  /// A configured [DartRulesSource] for a `WORKSPACE`.
  final DartRulesSource dartRulesSource;

  /// A path to find 'pub'.
  ///
  /// If `null` implicitly defaults to your PATH.
  final String pubExecutable;

  /// A directory where `pubspec.yaml` is present.
  final String pubPackageDir;

  /// Create a new set of arguments for how to run `bazelify`.
  ///
  /// Will be executed locally to where [pubPackageDir] is. For example,
  /// assuming the following directory structure, the directory could be
  /// `projects/foo_bar`:
  ///
  ///   ```
  ///   - projects
  ///     - foo_bar
  ///       pubspec.yaml
  ///   ```
  ///
  /// Options:
  /// - [bazelExecutable]: Where to find `bazel`. Defaults to your PATH.
  /// - [pubExecutable]: Where to find `pub`. Defaults to your PATH.
  /// - [pubPackageDir]: Where a package with a `pubspec.yaml` is. Defaults to
  ///   the current working directory.
  BazelifyArguments({
    this.bazelExecutable,
    this.dartRulesSource: DartRulesSource.stable,
    this.pubExecutable,
    this.pubPackageDir,
  });

  /// Returns a new [BazelifyArguments] by parsing [args].
  factory BazelifyArguments.parse(List<String> args) {
    final result = _argParser.parse(args);
    var source = DartRulesSource.stable;
    if (result.wasParsed('rules-commit')) {
      source = new DartRulesSource.commit(result['rules-commit']);
    } else if (result.wasParsed('rules-tag')) {
      source = new DartRulesSource.tag(result['rules-tag']);
    } else if (result.wasParsed('rules-local')) {
      source = new DartRulesSource.local(result['rules-local']);
    }
    return new BazelifyArguments(
      bazelExecutable: result['bazel'],
      dartRulesSource: source,
      pubExecutable: result['pub'],
      pubPackageDir: result['package'],
    );
  }

  /// Whether all properties are set.
  ///
  /// If `false`, use [resolve] to find them on the PATH/CWD.
  bool get isResolved =>
      pubPackageDir != null && bazelExecutable != null && pubExecutable != null;

  /// Returns a [Future] that completes with a new [BazelifyArguments].
  ///
  /// Any implicitly default executable path is resolved to the actual location
  /// on the user's PATH, and missing executables throw a [StateError].
  Future<BazelifyArguments> resolve() async {
    if (isResolved) {
      return this;
    }
    String bazelResolved = bazelExecutable;
    if (bazelResolved == null) {
      bazelResolved = await which('bazel');
    } else {
      if (!await FileSystemEntity.isFile(bazelResolved)) {
        throw new StateError('No "bazel" found at "$bazelResolved"');
      }
    }
    String pubResolved = pubExecutable;
    if (pubResolved == null) {
      pubResolved = await which('pub');
    } else {
      if (!await FileSystemEntity.isFile(pubResolved)) {
        throw new StateError('No "pub" found at "$pubResolved"');
      }
    }

    String workspaceResolved = p.normalize(pubPackageDir ?? p.current);
    if (workspaceResolved == null) {
      workspaceResolved = p.current;
    }
    var pubspec = p.join(workspaceResolved, 'pubspec.yaml');
    if (!await FileSystemEntity.isFile(pubspec)) {
      throw new StateError('No "pubspec" found at "${p.absolute(pubspec)}"');
    }
    return new BazelifyArguments(
      bazelExecutable: bazelResolved,
      dartRulesSource: dartRulesSource,
      pubExecutable: pubResolved,
      pubPackageDir: workspaceResolved,
    );
  }
}

/// Where to retrieve the `rules_dart`.
abstract class DartRulesSource {
  /// The default version of [DartRulesSource] if not otherwise specified.
  static const DartRulesSource stable =
      const DartRulesSource.tag('0.1.0');

  /// Use a git [commit].
  const factory DartRulesSource.commit(String commit) = _GitCommitRulesSource;

  /// Use a file [path].
  const factory DartRulesSource.local(String path) = _LocalRulesSource;

  /// Use a git [tag].
  const factory DartRulesSource.tag(String tag) = _GitTagRulesSource;
}

class _LocalRulesSource implements DartRulesSource {
  final String _path;

  const _LocalRulesSource(this._path);

  @override
  String toString() => 'local_repository(\n'
      '    name = "io_bazel_rules_dart",\n'
      '    path = "$_path",\n'
      ')\n';
}

class _GitCommitRulesSource implements DartRulesSource {
  final String _commit;

  const _GitCommitRulesSource(this._commit);

  @override
  String toString() => 'git_repository(\n'
      '    name = "io_bazel_rules_dart",\n'
      '    remote = "https://github.com/dart-lang/rules_dart",\n'
      '    commit = "$_commit",\n'
      ')\n';
}

class _GitTagRulesSource implements DartRulesSource {
  final String _tag;

  const _GitTagRulesSource(this._tag);

  @override
  String toString() => 'git_repository(\n'
      '    name = "io_bazel_rules_dart",\n'
      '    remote = "https://github.com/dart-lang/rules_dart",\n'
      '    tag = "$_tag",\n'
      ')\n';
}
