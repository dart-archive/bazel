import 'dart:async';
import 'dart:io';

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

  Future/*<T>*/ run/*<T>*/(String description, Future/*<T>*/ step(),
      {bool printCompleteOnNewLine = false}) async {
    assert(_stopwatch.isRunning);
    var start = _stopwatch.elapsed;
    try {
      stdout.write('$_elapsed: $description');
      if (printCompleteOnNewLine) stdout.writeln();
      return await step();
    } finally {
      var elapsedMillis = (_stopwatch.elapsed - start).inMilliseconds;
      if (printCompleteOnNewLine) {
        stdout.write('$_elapsed: $description finished');
      }
      stdout.writeln(' (${elapsedMillis}ms)');
    }
  }

  void complete(String message) {
    stdout.writeln('$_elapsed: $message');
    _stopwatch.stop();
  }
}

final _elapsedRegexp = new RegExp(r'^(0*:)*');
