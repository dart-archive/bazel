import 'package:test/test.dart';

import 'package:bazel/src/bazelify/bazelify_config.dart';
import 'package:bazel/src/bazelify/build.dart';
import 'package:bazel/src/bazelify/pubspec.dart';

void main() {
  test('bazelify.yaml can be parsed', () {
    var pubspec = new Pubspec.parse(pubspecYaml);
    var bazelifyConfig = new BazelifyConfig.parse(pubspec, bazelifyYaml);
    expectDartLibraries(
        bazelifyConfig.dartLibraries,
        {
          'a': new DartLibrary(
              name: 'a',
              package: 'example',
              dependencies: ['b', 'c:d'],
              sources: ['lib/a.dart', 'lib/src/a/**']),
          'e': new DartLibrary(
              name: 'e',
              package: 'example',
              dependencies: ['f'],
              sources: ['lib/e.dart', 'lib/src/e/**'],
              isDefault: true),
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
    sources:
      - "lib/e.dart"
      - "lib/src/e/**"
''';

var pubspecYaml = '''
name: example
dependencies:
  a: 1.0.0
  b: 2.0.0
''';

void expectDartLibraries(Map<String, DartLibrary> actual, Map<String, DartLibrary> expected) {
  expect(actual.keys, unorderedEquals(expected.keys));
  for (var p in actual.keys) {
    expect(actual[p], equals(new _DartLibraryMatcher(expected[p])));
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
      equals(_expected.dependencies).matches(item.dependencies, _) &&
      equals(_expected.sources).matches(item.sources, _);

  @override
  Description describe(Description description) =>
      description.addDescriptionOf('${_expected.package}:${_expected.name}\n'
          'sources: ${_expected.sources}\n'
          'dependencies: ${_expected.sources}\n'
          'isDefault: ${_expected.isDefault}');
}
