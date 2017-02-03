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

  /// Runs [step], printing the current elapsed time followed by [description].
  ///
  /// When [step] completes if [printCompleteOnNewLine] is false, then it will
  /// just append the time in milliseconds to the same line, otherwise it will
  /// print a new line with the elapsed time.
  ///
  /// If the action might do some of its own logging, then you should pass
  /// `printCompleteOnNewLine: true` to this method for ideal output.
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

  /// Stops the timer, and logs [message].
  void complete([String message]) {
    if (message != null) stdout.writeln('$_elapsed: $message');
    _stopwatch.stop();
  }
}

final _elapsedRegexp = new RegExp(r'^(0*:)*');
