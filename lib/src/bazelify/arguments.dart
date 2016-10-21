// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:which/which.dart';

/// Shared arguments between all bazelify commands.
class BazelifyArguments {
  static final ArgParser _argParser = () {
    var parser = new ArgParser()
      ..addOption(
        'bazel',
        help: 'A path to the "bazel" executable. Defauls to your PATH.',
      )
      ..addOption(
        'package',
        abbr: 'p',
        help: 'A directory where "pubspec.yaml" is present. Defaults to CWD.',
      );

    parser.addCommand(
        BazelifyInitArguments.command, BazelifyInitArguments._argParser);
    parser.addCommand(
        BazelifyServeArguments.command, BazelifyServeArguments._argParser);

    return parser;
  }();

  static String getUsage() => _argParser.usage;

  BazelifyArguments._({this.bazelExecutable, this.pubPackageDir});

  /// Returns a concrete subtype of [BazelifyArguments] based on the command
  /// found in [args].
  static Future<BazelifyArguments> parse(List<String> args) async {
    final result = _argParser.parse(args);

    String bazelResolved = result['bazel'];
    if (bazelResolved == null) {
      bazelResolved = await which('bazel');
    } else {
      if (!await FileSystemEntity.isFile(bazelResolved)) {
        throw new StateError('No "bazel" found at "$bazelResolved"');
      }
    }

    var pubPackageDir = result['package'];

    String workspaceResolved = p.normalize(pubPackageDir ?? p.current);
    if (workspaceResolved == null) {
      workspaceResolved = p.current;
    }

    var pubspec = p.join(workspaceResolved, 'pubspec.yaml');
    if (!await FileSystemEntity.isFile(pubspec)) {
      throw new StateError('No "pubspec" found at "${p.absolute(pubspec)}"');
    }

    switch (result.command?.name ?? BazelifyInitArguments.command) {
      case BazelifyServeArguments.command:
        return new BazelifyServeArguments._(
            bazelExecutable: bazelResolved,
            pubPackageDir: workspaceResolved,
            target: result.command['target'],
            watch: result.command != null
                ? result.command['watch'] as List<String>
                : null);
      case BazelifyInitArguments.command:
      default:
        var source = DartRulesSource.stable;
        if (result.command?.wasParsed('rules-commit') == true) {
          source = new DartRulesSource.commit(result.command['rules-commit']);
        } else if (result.command?.wasParsed('rules-tag') == true) {
          source = new DartRulesSource.tag(result.command['rules-tag']);
        } else if (result.command?.wasParsed('rules-local') == true) {
          source = new DartRulesSource.local(result.command['rules-local']);
        }

        String pubResolved =
            result.command != null ? result.command['pub'] : null;
        if (pubResolved == null) {
          pubResolved = await which('pub');
        } else {
          if (!await FileSystemEntity.isFile(pubResolved)) {
            throw new StateError('No "pub" found at "$pubResolved"');
          }
        }

        return new BazelifyInitArguments._(
            bazelExecutable: bazelResolved,
            dartRulesSource: source,
            pubExecutable: pubResolved,
            pubPackageDir: workspaceResolved);
    }
  }

  /// A path to the 'bazel' executable.
  ///
  /// If `null` implicitly defaults to your PATH.
  final String bazelExecutable;

  /// A directory where `pubspec.yaml` is present.
  final String pubPackageDir;
}

/// Arguments when running `bazelify init`, which adds Bazel support on top of
/// pub.
class BazelifyInitArguments extends BazelifyArguments {
  /// The name of this command.
  static const command = 'init';

  /// Parser for arguments specific to the this command.
  static final _argParser = new ArgParser()
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
    );

  /// A configured [DartRulesSource] for a `WORKSPACE`.
  final DartRulesSource dartRulesSource;

  /// A path to find 'pub'.
  ///
  /// If `null` implicitly defaults to your PATH.
  final String pubExecutable;

  /// Create a new set of arguments for how to run `bazelify init`.
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
  BazelifyInitArguments._({
    String bazelExecutable,
    this.dartRulesSource: DartRulesSource.stable,
    this.pubExecutable,
    String pubPackageDir,
  })
      : super._(bazelExecutable: bazelExecutable, pubPackageDir: pubPackageDir);
}

class BazelifyServeArguments extends BazelifyArguments {
  /// The name of this command.
  static const command = 'serve';

  /// Parser for arguments specific to the this command.
  static final _argParser = new ArgParser()
    ..addOption('watch',
        allowMultiple: true,
        defaultsTo: 'web,lib,pubspec.lock',
        help: 'A list of files/directories to watch for changes and trigger '
            ' builds')
    ..addOption('target',
        defaultsTo: 'main_ddc_serve',
        help: 'The name of the server build target to run.',
        hide: true);

  /// The folders and/or files to watch and trigger builds.
  final List<String> watch;

  /// The server build target to run.
  final String target;

  BazelifyServeArguments._({
    String bazelExecutable,
    String pubPackageDir,
    this.target,
    this.watch,
  })
      : super._(bazelExecutable: bazelExecutable, pubPackageDir: pubPackageDir);
}

/// Where to retrieve the `rules_dart`.
abstract class DartRulesSource {
  /// The default version of [DartRulesSource] if not otherwise specified.
  static const DartRulesSource stable = const DartRulesSource.tag('0.1.1');

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
