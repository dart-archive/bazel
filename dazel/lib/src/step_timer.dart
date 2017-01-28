import 'dart:async';

class StepTimer {
  final timings = <String, Duration>{};

  Future/*<T>*/ run/*<T>*/(String description, Future/*<T>*/ step()) async {
    final stopwatch = new Stopwatch()..start();
    try {
      return await step();
    } finally {
      timings[description] = stopwatch.elapsed;
    }
  }

  void printTimings() {
    timings.forEach((name, duration) {
      print('$name took ${duration.inMilliseconds}ms');
    });
  }
}
