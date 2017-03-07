import 'dart:io';

import 'package:dazel/src/bazelify/initialize.dart';
import 'package:dazel/src/bazelify/workspace.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  Workspace workspace;

  String loadGolden(String path) {
    return new File(p.normalize('test/goldens/$path')).readAsStringSync();
  }

  test('should load a git-tagged repository', () {
    workspace = new Workspace.fromDartSource(
        new DartRulesSource.tag('0.0.1-alpha'), null);
    expect(workspace.toString(), loadGolden('workspace_git_tagged'));
  });

  test('should load a git-commit repository', () {
    workspace = new Workspace.fromDartSource(
        new DartRulesSource.commit('1a2b3c4d'), null);
    expect(workspace.toString(), loadGolden('workspace_git_commit'));
  });

  test('should load a local repository', () {
    workspace = new Workspace.fromDartSource(
        new DartRulesSource.local('/usr/somebody/git/rules_dart'), null);
    expect(workspace.toString(), loadGolden('workspace_local'));
  });

  test('should load a repository with a local SDK', () async {
    workspace = new Workspace.fromDartSource(
        new DartRulesSource.tag('0.0.1-alpha'), 'path/to/sdk');
    expect(workspace.toString(), loadGolden('workspace_local_sdk'));
  });
}
