[Bazel][bazel] extension support for [Dart][dart].

Bazel is a _correct, reproducible, and fast_ build tool used internally at
Google, and now open source, that provides a powerful and extensible framework
for building software and maintaining code.

[bazel]: https://www.bazel.io/
[dart]: https://www.dartlang.org/

## Why Bazel

Large applications in Google like [AdWords Next][blog-awn] and
[AdSense][blog-ads] have used Dart and [Angular Dart][angular-dart] in
production with Bazel for a while, and now we want to share Bazel with the rest
of the community.

[blog-awn]: http://news.dartlang.org/2016/03/the-new-adwords-ui-uses-dart-we-asked.html
[blog-ads]: http://news.dartlang.org/2016/10/google-adsense-angular-dart.html
[angular-dart]: https://angular.io/dart


## Getting Started

[file-issue]: https://github.com/dart-lang/bazel/issues/new

> **WARNING**: This package is highly experimental. While the underlying
> framework (such as BUILD rules and extensions) are stable, we're still
> iterating on a good stable solution for end users that are used to primarily
> working with pub and `pubspec.yaml` files.
>
> Have a suggestion to make this better? [File an issue][file-issue].

The dazel package publishes a `dazel` command that takes an existing pub
package and automatically generates a Bazel workspace: full of extensions,
macros, rules, and more.
