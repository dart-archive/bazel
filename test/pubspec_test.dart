import 'package:test/test.dart';

import 'package:bazel/src/bazelify/pubspec.dart';


void main() {
  test('pubspec yaml can be parsed', () {
    var pubspec = new Pubspec.parse(exampleYaml);
    expect(pubspec.pubPackageName, equals('example'));
    expect(pubspec.dependencies, equals(['a', 'b']));
    expect(pubspec.devDependencies, equals(['c', 'd']));
    expect(
        pubspec.transformers,
        equalsTransformers([
          new Transformer('a'),
          new Transformer('b', config: {
            'foo': 'bar',
          }),
          new Transformer('c'),
          new Transformer('d', config: {
            'hello': 'world',
          }),
        ]));
  });

  test('uris can be created correctly', () {
    expect(new Transformer('a').uri, equals(Uri.parse('package:a/a.dart')));
    expect(new Transformer('a/b').uri, equals(Uri.parse('package:a/b.dart')));
  });
}

var exampleYaml = '''
name: example
dependencies:
  a: 1.0.0
  b: 2.0.0
dev_dependencies:
  c: 1.0.0
  d: 2.0.0
transformers:
- a
- b:
    foo: bar
- c:
- d:
    hello: world
''';

Matcher equalsTransformers(Iterable<Transformer> expected) =>
    equals(expected.map((e) => new _TransformerMatcher(e)));

class _TransformerMatcher extends Matcher {
  final Transformer _expected;
  _TransformerMatcher(this._expected);

  bool matches(item, _) =>
      item is Transformer &&
      item.name == _expected.name &&
      item.uri == _expected.uri &&
      equals(_expected.config).matches(item.config, _);

  Description describe(Description description) =>
      description.addDescriptionOf(_expected);
}
