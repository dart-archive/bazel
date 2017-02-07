import 'build.dart';

/// A generator for a `codegen.bzl` file which defines the `dart_codegen_rule`
/// rules for a package.
class CodegenRulesFile {
  final Map<String, DartBuilderBinary> builderDefinitions;

  CodegenRulesFile(this.builderDefinitions);

  @override
  String toString() {
    var codegenRules = new StringBuffer()
      ..writeln('load(')
      ..writeln('    "${BuildFile.codegenBzl}",')
      ..writeln('    "dart_codegen_rule"')
      ..writeln(')');
    for (var builder in builderDefinitions.values) {
      codegenRules.writeln(builder.toCodegenRule());
    }
    return '$codegenRules';
  }
}
