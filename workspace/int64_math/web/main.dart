import 'package:angular2/angular2.dart';
import 'package:angular2/platform/browser.dart';

@Component(selector: 'hello', template: 'Hello World')
class HelloWorldComponent {}

void main() {
  bootstrap(HelloWorldComponent);
}
