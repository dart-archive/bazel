import 'package:args/command_runner.dart';

import 'initialize.dart' show InitCommand;
import 'serve.dart' show ServeCommand;

class BazelifyCommandRunner extends CommandRunner {
  BazelifyCommandRunner()
      : super('bazelify', 'Bootstrap your Dart package with Bazel.') {
    argParser
      ..addOption('bazel',
          help: 'A path to the "bazel" executable. Defauls to your PATH.')
      ..addOption('package',
          abbr: 'p',
          help: 'A directory where "pubspec.yaml" is present. '
              'Defaults to CWD.');

    addCommand(new InitCommand());
    addCommand(new ServeCommand());
  }
}
