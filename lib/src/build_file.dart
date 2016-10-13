import 'pubspec.dart';

/// A generator for bazel BUILD files.
///
/// Every pub package corresponds to a single `dart_library` rule.
class BuildFile {
  final Pubspec pubspec;

  BuildFile(this.pubspec);

  final String preamble = '''
load("@io_bazel_rules_dart//dart/build_rules:core.bzl", "dart_library")
package(default_visibility = ["//visibility:public"])
''';

  String get libraryRule => '''
dart_library(
    name = "${pubspec.packageName}",
    srcs = glob(["lib/**"]),
    deps = [${pubspec.deps.map((dep) => '\n        "$dep",').join()}
    ],
)
''';
  String forRepository() => '''
$preamble
$libraryRule
''';
}
