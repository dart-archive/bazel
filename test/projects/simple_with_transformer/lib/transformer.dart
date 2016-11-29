import 'package:barback/barback.dart';

class MyTransformer extends Transformer {
  final BarbackSettings settings;

  MyTransformer(this.settings);
  MyTransformer.asPlugin(this.settings);

  @override
  apply(_) => throw new UnimplementedError('unimplemented!');
}

class MyTransformerGroup implements TransformerGroup {
  final BarbackSettings settings;

  MyTransformerGroup(this.settings);
  MyTransformerGroup.asPlugin(this.settings);

  @override
  Iterable<Iterable> get phases => [
    [
      new MyTransformer(settings),
    ],
    [
      new MyTransformer(settings),
      new MyOtherTransformerGroup(settings),
    ],
  ];
}

class MyOtherTransformerGroup implements TransformerGroup {
  final BarbackSettings settings;

  MyOtherTransformerGroup(this.settings);

  @override
  Iterable<Iterable> get phases => [
    [
      new MyTransformer(settings),
    ],
  ];
}
