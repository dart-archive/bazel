import 'dart:async';
import 'dart:io';

import 'package:bazel/src/bazelify/arguments.dart';
import 'package:bazel/src/bazelify/generate.dart';
import 'package:stack_trace/stack_trace.dart';

Future<Null> main(List<String> args) async {
  // Parse into an object.
  BazelifyArguments arguments;
  try {
    arguments = new BazelifyArguments.parse(args);
    // Massage the arguments based on defaults.
    arguments = await arguments.resolve();
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

  await Chain.capture(() => generate(arguments), onError: (error, chain) {
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
