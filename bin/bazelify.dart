import 'dart:async';
import 'dart:io';

import 'package:bazel/src/bazelify/arguments.dart';
import 'package:bazel/src/bazelify/generate.dart';
import 'package:bazel/src/bazelify/serve.dart';
import 'package:stack_trace/stack_trace.dart';

Future<Null> main(List<String> args) async {
  // Parse into an object.
  BazelifyArguments arguments;
  try {
    arguments = await BazelifyArguments.parse(args);
  } on ArgumentError catch (e) {
    if (e.name != null) {
      _printArgumentError(e);
    } else {
      rethrow;
    }
    _printUsage();
    exitCode = 64;
    return;
  }

  await Chain.capture(() async {
    if (arguments is BazelifyInitArguments) {
      await generate(arguments);
    } else if (arguments is BazelifyServeArguments) {
      await serve(arguments);
    } else {
      throw new StateError('Something has gone horribly wrong, please file a '
          'bug at http://github.com/dart-lang/bazel');
    }
  }, onError: (error, chain) {
    print(error);
    print(chain.terse);
    exitCode = 1;
  });
}

void _printArgumentError(ArgumentError e) {
  print('Invalid arguments: ${e.message}');
}

void _printUsage() {
  print(BazelifyArguments.getUsage());
}
