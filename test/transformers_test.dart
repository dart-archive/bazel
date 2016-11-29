import 'package:barback/barback.dart';
import 'package:dart_style/dart_style.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:bazel/src/bazelify/pubspec.dart' as pubspec;
import 'package:bazel/src/bazelify/transformers.dart';

import 'projects/simple_with_transformer/lib/transformer.dart';

void main() {
  test('createTransformersInLibrary', () {
    var mode = new BarbackMode("debug");
    var config = {'hello': 'world'};
    var libraryUri = new Uri.file(p.absolute(
        'test/projects/simple_with_transformer/lib/transformer.dart'));

    var transformers = createTransformersInLibrary(libraryUri, config, mode);
    expect(transformers.length, 2);
    expect(transformers[0] is MyTransformer, isTrue);
    var first = transformers[0] as MyTransformer;
    expect(first.settings.configuration, config);
    expect(first.settings.mode, mode);
    expect(transformers[1] is MyTransformerGroup, isTrue);
    var second = transformers[1] as MyTransformerGroup;
    expect(second.settings.configuration, config);
    expect(second.settings.mode, mode);
    // Note that we shouldn't see `MyOtherTransformerGroup`, since it doesn't
    // have an `asPlugin` constructor.
  });

  test('bootstrapTransformersFromPubpec', () {
    var bootstrapContent = bootstrapTransformersFromPubpec(
      new pubspec.Pubspec.parse('''
          name: example
          transformers:
          - foo/bar
          - baz/zap:
              hello: world
          - zip:
              zorp:
              - a
              - b
              - c
          '''));
    expect(bootstrapContent, equalsFormatted('''
        import "dart:convert";
        import "package:barback/barback.dart";
        import "package:bazel/src/bazelify/transformers.dart";
        import "package:foo/bar.dart";
        import "package:baz/zap.dart";
        import "package:zip/zip.dart";

        Iterable<Iterable> buildTransformers({BarbackMode mode}) {
          mode ??= new BarbackMode("release");
          var transformers = [];
          transformers.add(createTransformersInLibrary(
              Uri.parse('package:foo/bar.dart'),
              JSON.decode('{}'),
              mode));
          transformers.add(createTransformersInLibrary(
              Uri.parse('package:baz/zap.dart'),
              JSON.decode('{"hello":"world"}'),
              mode));
          transformers.add(createTransformersInLibrary(
              Uri.parse('package:zip/zip.dart'),
              JSON.decode('{"zorp":["a","b","c"]}'),
              mode));
          return transformers;
        }'''));
  });
}

final _formatter = new DartFormatter();

Matcher equalsFormatted(String code) => new _FormattedStringMatcher(code);

class _FormattedStringMatcher extends Matcher {
  final String _expected;
  _FormattedStringMatcher(String expected)
      : _expected = _formatter.format(expected);

  @override
  bool matches(check, _) {
    try {
      var formatted = _formatter.format(check);
      return formatted == _expected;
    } catch(_) {
      return false;
    }
  }

  @override
  Description describe(Description description) =>
      description.addDescriptionOf(_expected);
}
