import 'package:test/test.dart';

import 'package:bazel/src/bazelify/bazelify_config.dart';
import 'package:bazel/src/bazelify/build.dart';
import 'package:bazel/src/bazelify/pubspec.dart';

void main() {
  test('bazelify.yaml can be parsed', () {
    var pubspec = new Pubspec.parse(pubspecYaml);
    var bazelifyConfig = new BazelifyConfig.parse(pubspec, bazelifyYaml);
    expectDartLibraries(bazelifyConfig.dartLibraries, {
      'a': new DartLibrary(
          name: 'a',
          package: 'example',
          dependencies: ['b', 'c:d'],
          sources: ['lib/a.dart', 'lib/src/a/**']),
      'e': new DartLibrary(
          name: 'e',
          package: 'example',
          dependencies: ['f', ':a'],
          sources: ['lib/e.dart', 'lib/src/e/**'],
          excludeSources: ['lib/src/e/g.dart'],
          isDefault: true,
          enableDdc: false),
    });
  });
}

var bazelifyYaml = '''
targets:
  a:
    dependencies:
      - b
      - c:d
    sources:
      - "lib/a.dart"
      - "lib/src/a/**"
  e:
    default: true
    dependencies:
      - f
      - :a
    sources:
      - "lib/e.dart"
      - "lib/src/e/**"
    exclude_sources:
      - "lib/src/e/g.dart"
    platforms:
      - vm
''';

var pubspecYaml = '''
name: example
dependencies:
  a: 1.0.0
  b: 2.0.0
''';

void expectDartLibraries(
    Map<String, DartLibrary> actual, Map<String, DartLibrary> expected) {
  expect(actual.keys, unorderedEquals(expected.keys));
  for (var p in actual.keys) {
    expect(actual[p], new _DartLibraryMatcher(expected[p]));
  }
}

class _DartLibraryMatcher extends Matcher {
  final DartLibrary _expected;
  _DartLibraryMatcher(this._expected);

  @override
  bool matches(item, _) =>
      item is DartLibrary &&
      item.name == _expected.name &&
      item.package == _expected.package &&
      item.isDefault == _expected.isDefault &&
      item.enableDdc == _expected.enableDdc &&
      equals(_expected.dependencies).matches(item.dependencies, _) &&
      equals(_expected.sources).matches(item.sources, _) &&
      equals(_expected.excludeSources).matches(item.excludeSources, _);

  @override
  Description describe(Description description) =>
      description.addDescriptionOf(_expected);
}
