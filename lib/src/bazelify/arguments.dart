// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:which/which.dart';

const _installBazel = 'Please install bazel - '
    'https://www.bazel.io/versions/master/docs/install.html';

Future<BazelifyArguments> sharedArguments(ArgResults result) async {
  String bazelResolved = result['bazel'];
  if (bazelResolved == null) {
    try {
      bazelResolved = await which('bazel');
    } catch (_) {
      print('Could not find the command `bazel`\n');
      print(_installBazel);
      exitCode = 127;
      return null;
    }
  } else {
    if (!await FileSystemEntity.isFile(bazelResolved)) {
      print('`bazel` does not exist at $bazelResolved\n');
      print(_installBazel);
      exitCode = 127;
      return null;
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

  return new BazelifyArguments(
      bazelExecutable: bazelResolved, pubPackageDir: workspaceResolved);
}

/// Shared arguments between all bazelify commands.
class BazelifyArguments {
  BazelifyArguments({this.bazelExecutable, this.pubPackageDir});

  /// A path to the 'bazel' executable.
  ///
  /// If `null` implicitly defaults to your PATH.
  final String bazelExecutable;

  /// A directory where `pubspec.yaml` is present.
  final String pubPackageDir;
}
