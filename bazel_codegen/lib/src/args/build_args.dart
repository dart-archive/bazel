// Copyright (c) 2017, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
import 'dart:io';

import 'package:args/args.dart';
import 'package:logging/logging.dart';

const _rootDirParam = 'root-dir';
const _helpParam = 'help';
const _inExtension = 'in-extension';
const _logLevelParam = 'log-level';
const _logPathParam = 'log';
const _outExtension = 'out-extension';
const _outParam = 'out';
const _packagePathParam = 'package-path';
const _packageMapParam = 'package-map';
const _srcsParam = 'srcs-file';
const _summariesParam = 'use-summaries';

// All arguments other than `--help` and `--use-summaries` are required.
final _argParser = new ArgParser()
  ..addOption(_rootDirParam,
      allowMultiple: true,
      help: 'One or more workspace directories to check when reading files.')
  ..addFlag(_helpParam,
      abbr: 'h', negatable: false, help: 'Prints this message and exits')
  ..addOption(_inExtension, help: 'The file extension to process')
  ..addOption(_logLevelParam,
      allowed: _optionToLogLevel.keys.toList(),
      defaultsTo: 'warning',
      help: 'The minimum level of log to print to the console.')
  ..addOption(_logPathParam, help: 'The full path of the logfile to write')
  ..addOption(_outParam, abbr: 'o', help: 'The directory to write into.')
  ..addOption(_outExtension,
      allowMultiple: true, help: 'The file extension to output')
  ..addFlag(_summariesParam,
      negatable: true,
      defaultsTo: true,
      help: 'Whether to use summaries for analysis')
  ..addOption(_packagePathParam,
      help: 'The path of the package we are processing relative to CWD')
  ..addOption(_packageMapParam,
      help: 'Path to a file containing the path under the bazel roots to each '
          'package name.')
  ..addOption(_srcsParam,
      help: 'Path to a file containing all files to generate code for. '
          'Each line in this file is the path to a source to generate for. '
          'These are expected to be relative to CWD.');

Map<String, Level> _optionToLogLevel = {
  'fine': Level.FINE,
  'info': Level.INFO,
  'warning': Level.WARNING,
  'error': Level.SEVERE,
};

/// Parsed arguments for code generator binaries.
class BuildArgs {
  final List<String> rootDirs;
  final String packagePath;
  final String outDir;
  final Level logLevel;
  final String logPath;
  final String inputExtension;
  final List<String> outputExtensions;
  final String packageMapPath;
  final String srcsPath;
  final bool help;
  final bool isWorker;
  final bool useSummaries;
  final List<String> additionalArgs;

  BuildArgs._(
      this.rootDirs,
      this.packagePath,
      this.outDir,
      this.logPath,
      this.inputExtension,
      this.outputExtensions,
      this.packageMapPath,
      this.srcsPath,
      this.help,
      this.logLevel,
      {this.isWorker,
      this.useSummaries: true,
      this.additionalArgs});

  factory BuildArgs.parse(List<String> args, {bool isWorker}) {
    // When not running as a worker, but that mode is supported, then we get
    // just this arg which points at a file containing the arguments.
    if (args.length == 1 && args.first.startsWith('@')) {
      args = new File(args.first.substring(1)).readAsLinesSync();
    }

    final argResults = _argParser.parse(args);

    final rootDirs = _requiredArg(argResults, _rootDirParam);
    final packagePath = _requiredArg(argResults, _packagePathParam);
    final outDir = _requiredArg(argResults, _outParam);
    final logLevel =
        _optionToLogLevel[_requiredArg(argResults, _logLevelParam)];

    final logPath = _requiredArg(argResults, _logPathParam);
    final inputExtension = _requiredArg(argResults, _inExtension);
    final outputExtensions = _requiredArg(argResults, _outExtension);

    final packageMapPath = _requiredArg(argResults, _packageMapParam);
    final srcsPath = _requiredArg(argResults, _srcsParam);
    final help = argResults[_helpParam];
    final useSummaries = argResults[_summariesParam];

    return new BuildArgs._(
        rootDirs,
        packagePath,
        outDir,
        logPath,
        inputExtension,
        outputExtensions,
        packageMapPath,
        srcsPath,
        help,
        logLevel,
        additionalArgs: argResults.rest,
        isWorker: isWorker,
        useSummaries: useSummaries);
  }

  void printUsage() {
    print('Usage: dart ${Platform.script.pathSegments.last} '
        '<options(s)> <Additional args for generator>');
    print('All options are required');
    print('Options:\n${_argParser.usage}');
  }
}

dynamic _requiredArg(ArgResults results, String param) {
  final val = results[param];
  if (val == null) throw new ArgumentError.notNull(param);
  return val;
}
