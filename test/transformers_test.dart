import 'package:barback/barback.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:bazel/src/bazelify/transformers.dart';

import 'projects/simple_with_transformer/lib/transformer.dart';

void main() {
  test('can instantiate transformers from imported libraries', () {
    var mode = new BarbackMode("debug");
    var config = {'hello': 'world'};
    var libraryUri = new Uri.file(p.absolute(
        'test/projects/simple_with_transformer/lib/transformer.dart'));

    var transformers = createTransformersInLibrary(libraryUri, config, mode);
    expect(transformers.length, 1);
    expect(transformers.first is MyTransformer, isTrue);
    var myTransformer = transformers.first as MyTransformer;
    expect(myTransformer.settings.configuration, config);
    expect(myTransformer.settings.mode, mode);
  });
}
