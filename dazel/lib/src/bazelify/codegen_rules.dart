import 'bazelify_config.dart';
import 'build.dart';

/// A generator for a `codegen.bzl` file which defines the `dart_codegen_rule`
/// values.
class CodegenRulesFile {
  final Set<String> buildersConsumed;
  final Map<String, DartBuilderBinary> builderDefinitions;

  factory CodegenRulesFile(BazelifyConfig consumingPackage,
      Map<String, BazelifyConfig> allPackages) {
    var buildersConsumed = new Set<String>();
    for (var library in consumingPackage.dartLibraries.values) {
      buildersConsumed.addAll(library.builders.keys);
    }
    var builderDefinitions = <String, DartBuilderBinary>{};
    for (var package in allPackages.values) {
      builderDefinitions.addAll(package.dartBuilderBinaries);
    }
    return new CodegenRulesFile._(buildersConsumed, builderDefinitions);
  }

  CodegenRulesFile._(this.buildersConsumed, this.builderDefinitions);

  @override
  String toString() {
    var codegenRules = new StringBuffer()
      ..writeln('load(')
      ..writeln('    "${BuildFile.codegenBzl}",')
      ..writeln('    "dart_codegen_rule"')
      ..writeln(')');
    for (var builder in buildersConsumed) {
      codegenRules.writeln(builderDefinitions[builder].toCodegenRule());
    }
    return '$codegenRules';
  }
}
