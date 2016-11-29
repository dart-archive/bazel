import 'package:barback/barback.dart';

class MyTransformer extends Transformer {
  final BarbackSettings settings;

  MyTransformer.asPlugin(this.settings);

  @override
  apply(_) => throw new UnimplementedError('unimplemented!');
}
