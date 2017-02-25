# 0.1.0

- Wrap generation in Chain.capture and print full asynchronous stack traces
- **BREAKING** `bazelGenerate` and `noArgs` have been dropped. These are unused
  from the template file in `rules_dart` which is the supported approach.

# 0.0.3

- Only read '.dart' files as sources for the Resolver. This avoids a problem
  trying to read binary assets as if they were strings. Poorly encoded .dart
  files can still cause an error - but this case we'd expect to fail.
- Fix a bug where failure to read an asset during the Resolvers.get call would
  cause the entire process to hang.
- Rely on the print capturing from package:build

# 0.0.2

- Bug fix: Correct the import after library was renamed with a leading
  underscore.
