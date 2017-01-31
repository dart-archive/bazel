import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dazel/src/bazelify/command_runner.dart';
import 'package:dazel/src/bazelify/exceptions.dart';
import 'package:stack_trace/stack_trace.dart';

Future<Null> main(List<String> args) async {
  var runner = new BazelifyCommandRunner();

  await Chain.capture(() async {
    await runner.run(args);
  }, onError: (error, chain) {
    if (error is UsageException) {
      print(error.message);
      print(error.usage);
      exitCode = 64;
    } else if (error is ApplicationFailedException) {
      print(error.message);
      exitCode = error.exitCode;
      return;
    } else {
      print('Whoops! You may have discovered a bug in `bazelify` :(.\n'
          'Please file an issue at http://github.com/dart-lang/bazel');
      print(error);
      print(chain.terse);
      exitCode = 1;
    }
  });
}
