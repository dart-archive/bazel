import 'dart:async';

class StepTimer {
  final _stopwatch = new Stopwatch()..start();

  String get _elapsed {
    var elapsed = "${_stopwatch.elapsed}";

    // Strip of empty segments of the time.
    var match = _elapsedRegexp.firstMatch(elapsed);
    if (match != null) elapsed = elapsed.substring(match.end);

    // Only show 3 digits of precision.
    return elapsed.substring(0, elapsed.length - 3);
  }

  Future/*<T>*/ run/*<T>*/(String description, Future/*<T>*/ step()) async {
    try {
      print('$_elapsed: $description');
      return await step();
    } finally {}
  }

  void complete(String message) {
    print('$_elapsed: $message');
    _stopwatch.stop();
  }
}

final _elapsedRegexp = new RegExp(r'^(0*:)*');
