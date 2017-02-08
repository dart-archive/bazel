import 'dart:html';

import 'package:path/path.dart' as p;

void main() {
  document.body.text = p.join("Hello", "World");
}
