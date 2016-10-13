import 'dart:async';
import 'dart:io';

import 'package:bazel/src/arguments.dart';
import 'package:bazel/src/bin.dart';
import 'package:stack_trace/stack_trace.dart';

Future<Null> main(List<String> args) async {
  // Parse into an object.
  BazelifyArguments arguments;
  try {
    arguments = new BazelifyArguments.parse(args);
  } on ArgumentError catch (e) {
    if (e.name != null) {
      _printArgumentError(e);
    } else {
      rethrow;
    }
    _printUsage();
    exit(1);
  }

  await Chain.capture(() => work(arguments), onError: (error, chain) {
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
