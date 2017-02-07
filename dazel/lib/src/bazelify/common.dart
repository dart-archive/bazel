// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import 'build.dart';

void addAppArg(ArgParser argParser, {String defaultsTo}) {
  argParser.addOption('app',
      defaultsTo: defaultsTo,
      help: 'The name of the app target to build, this is the name of the '
          'html file for the app. This argument may be provided as a '
          'positional argument as well.');
}

/// Returns the bazel target given the `--app` argument in [argResults], or
/// uses the first extra argument if there is only one.
///
/// If [ddc] is `true` then the ddc server target will be returned, otherwise
/// the dart application (dart2js) target is returned.
///
/// Throws a [UsageException] if a suitable argument cannot be found.
String targetFromAppArgs(ArgResults argResults, ArgParser argParser,
    {bool ddc: false}) {
  var app;
  // Support providing `app` as a positional argument (and overriding the
  // default).
  if (!argResults.wasParsed('app') && argResults.rest.length == 1) {
    app = argResults.rest.first;
  } else {
    app = argResults['app'];
  }
  if (app == null) {
    throw new UsageException(
        'Missing required argument `app`', argParser.usage);
  }

  app = targetForAppPath(app);
  // Slight hack here, we don't want to modify the general serve target which is
  // the default, it's already correct.
  if (ddc && app != BuildFile.ddcServeAllName) app = ddcServeTarget(app);

  return app;
}

/// Returns the bazel target name given the path to an app (html file).
String targetForAppPath(String appPath) {
  // Target name doesn't have `.html`, but we want support for that for users.
  if (appPath.endsWith('.html')) appPath = p.withoutExtension(appPath);
  return p.split(appPath).join("__");
}

/// Returns the app path given a bazel target name.
String appPathForTarget(String target) =>
    '${p.joinAll(target.split('__'))}.html';

/// The name of the ddc server target corresponding to a web app target.
String ddcServeTarget(String webAppTarget) => '${webAppTarget}_ddc_serve';
