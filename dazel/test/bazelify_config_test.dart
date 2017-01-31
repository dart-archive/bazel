import 'package:test/test.dart';

import 'package:dazel/src/bazelify/bazelify_config.dart';
import 'package:dazel/src/bazelify/build.dart';
import 'package:dazel/src/bazelify/pubspec.dart';

void main() {
  test('bazelify.yaml can be parsed', () {
    var pubspec = new Pubspec.parse(pubspecYaml);
    var bazelifyConfig = new BazelifyConfig.parse(pubspec, bazelifyYaml);
    expectDartLibraries(bazelifyConfig.dartLibraries, {
      'a': new DartLibrary(
        builders: {
          'b:b': {},
          ':h': {'foo': 'bar'},
        },
        dependencies: ['b', 'c:d'],
        generateFor: [
          'lib/a.dart',
        ],
        name: 'a',
        package: 'example',
        sources: ['lib/a.dart', 'lib/src/a/**'],
      ),
      'e': new DartLibrary(
        dependencies: ['f', ':a'],
        enableDdc: false,
        excludeSources: ['lib/src/e/g.dart'],
        isDefault: true,
        name: 'e',
        package: 'example',
        sources: ['lib/e.dart', 'lib/src/e/**'],
      )
    });
    expectDartBuilderBinaries(bazelifyConfig.dartBuilderBinaries, {
      'h': new DartBuilderBinary(
        clazz: 'E',
        constructor: 'withSettings',
        import: 'package:example/e.dart',
        inputExtension: '.dart',
        name: 'h',
        outputExtensions: [
          '.g.dart',
          '.json',
        ],
        package: 'example',
        replacesTransformer: 'example',
        sharedPartOutput: true,
        target: 'e',
      ),
    });
  });
}

var bazelifyYaml = '''
targets:
  a:
    builders:
      - :h:
          foo: bar
      - b:b
    dependencies:
      - b
      - c:d
    generate_for:
      - lib/a.dart
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
builders:
  h:
    class: E
    constructor: withSettings
    import: package:example/e.dart
    input_extension: .dart
    output_extensions:
      - .g.dart
      - .json
    replaces_transformer: example
    shared_part_output: true
    target: e
''';

var pubspecYaml = '''
name: example
dependencies:
  a: 1.0.0
  b: 2.0.0
''';

void expectDartBuilderBinaries(Map<String, DartBuilderBinary> actual,
    Map<String, DartBuilderBinary> expected) {
  expect(actual.keys, unorderedEquals(expected.keys));
  for (var p in actual.keys) {
    expect(actual[p], new _DartBuilderBinaryMatcher(expected[p]));
  }
}

class _DartBuilderBinaryMatcher extends Matcher {
  final DartBuilderBinary _expected;
  _DartBuilderBinaryMatcher(this._expected);

  @override
  bool matches(item, _) =>
      item is DartBuilderBinary &&
      item.clazz == _expected.clazz &&
      item.constructor == _expected.constructor &&
      equals(_expected.dependencies).matches(item.dependencies, _) &&
      item.inputExtension == _expected.inputExtension &&
      item.import == _expected.import &&
      item.name == _expected.name &&
      equals(item.outputExtensions).matches(_expected.outputExtensions, _) &&
      item.package == _expected.package &&
      item.replacesTransformer == _expected.replacesTransformer &&
      item.sharedPartOutput == _expected.sharedPartOutput &&
      item.target == _expected.target;

  @override
  Description describe(Description description) =>
      description.addDescriptionOf(_expected);
}

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
      equals(_expected.builders).matches(item.builders, _) &&
      equals(_expected.dependencies).matches(item.dependencies, _) &&
      equals(_expected.generateFor).matches(item.generateFor, _) &&
      equals(_expected.sources).matches(item.sources, _) &&
      equals(_expected.excludeSources).matches(item.excludeSources, _);

  @override
  Description describe(Description description) =>
      description.addDescriptionOf(_expected);
}
