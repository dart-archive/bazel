import 'dart:io';

import 'package:dazel/src/bazelify/bazelify_config.dart';
import 'package:dazel/src/bazelify/codegen_rules.dart';
import 'package:dazel/src/bazelify/pubspec.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  String loadGolden(String path) {
    return new File(p.normalize('test/goldens/$path')).readAsStringSync();
  }

  test('should generate a codegen target for libraries', () async {
    final codegenAuthorPath = 'test/projects/codegen_author';
    final codegenAuthorPubspec =
        await Pubspec.fromPackageDir(codegenAuthorPath);
    final codegenAuthorConfig = await BazelifyConfig.fromPackageDir(
        codegenAuthorPubspec, codegenAuthorPath);
    final codegenRules =
        new CodegenRulesFile(codegenAuthorConfig.dartBuilderBinaries);
    expect(codegenRules.toString(), loadGolden('codegen_rules_codgen_author'));
  });
}
