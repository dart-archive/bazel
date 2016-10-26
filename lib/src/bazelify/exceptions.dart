class ApplicationFailedException implements Exception {
  final int exitCode;
  final String message;

  ApplicationFailedException(this.message, this.exitCode);
}
