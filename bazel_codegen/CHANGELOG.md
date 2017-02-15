# 0.0.3

- Only read '.dart' files as sources for the Resolver. This avoids a problem
  trying to read binary assets as if they were strings. Poorly encoded .dart
  files can still cause an error - but this case we'd expect to fail.
- Fix a bug where failure to read an asset during the Resolvers.get call would
  cause the entire process to hang.

# 0.0.2

- Bug fix: Correct the import after library was renamed with a leading
  underscore.
