// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:mirrors';

import 'package:barback/barback.dart' as barback;

import 'pubspec.dart';

/// The mirror system.
///
/// Cached to avoid re-instantiating each time a transformer is initialized.
final _mirrors = currentMirrorSystem();

/// Creates the contents of a library which exposes a `buildTransformers` method
/// that you can call to get concrete transformer phases from a `Pubspec`.
String bootstrapTransformersFromPubpec(Pubspec pubspec) {
  var sb = new StringBuffer();
  sb.writeln('import "dart:convert";');
  sb.writeln('import "package:barback/barback.dart";');
  sb.writeln('import "package:bazel/src/bazelify/transformers.dart";');

  for (var transformer in pubspec.transformers) {
    sb.writeln('import "${transformer.uri}";');
  }

  sb.writeln('Iterable<Iterable> buildTransformers({BarbackMode mode}) {');
  sb.writeln('mode ??= new BarbackMode("release");');
  sb.writeln('var transformers = [];');
  for (var transformer in pubspec.transformers) {
    sb.writeln('transformers.add(createTransformersInLibrary('
        'Uri.parse(\'${transformer.uri}\'), '
        'JSON.decode(\'${JSON.encode(transformer.config)}\'), '
        'mode));');
  }
  sb.writeln('return transformers;');
  sb.writeln('}');

  return sb.toString();
}

/// Loads all the transformers and groups defined in [uri].
///
/// Loads the library, finds any [Transformer] or [TransformerGroup] subclasses
/// in it, instantiates them with [configuration] and [mode], and returns them.
List createTransformersInLibrary(
    Uri uri, Map configuration, barback.BarbackMode mode) {
  var transformerClass = reflectClass(barback.Transformer);
  var aggregateClass = reflectClass(barback.AggregateTransformer);
  var groupClass = reflectClass(barback.TransformerGroup);

  var seen = new Set();
  var transformers = [];

  loadFromLibrary(library) {
    if (seen.contains(library)) return;
    seen.add(library);

    // Load transformers from libraries exported by [library].
    for (var dependency in library.libraryDependencies) {
      if (!dependency.isExport) continue;
      loadFromLibrary(dependency.targetLibrary);
    }
    var sortedDeclarations = library.declarations.values.toList()
      ..sort((a, b) => a.location.line.compareTo(b.location.line));
    transformers.addAll(sortedDeclarations.map((declaration) {
      if (declaration is! ClassMirror) return null;
      var classMirror = declaration as ClassMirror;
      if (classMirror.isPrivate) return null;
      if (classMirror.isAbstract) return null;
      if (!classMirror.isSubtypeOf(transformerClass) &&
          !classMirror.isSubtypeOf(groupClass) &&
          !classMirror.isSubtypeOf(aggregateClass)) {
        return null;
      }
      var constructor = _getConstructor(classMirror, 'asPlugin');
      if (constructor == null) return null;
      if (constructor.parameters.isEmpty) {
        if (configuration.isNotEmpty) return null;
        return classMirror.newInstance(const Symbol('asPlugin'), []).reflectee;
      }
      if (constructor.parameters.length != 1) return null;

      return classMirror.newInstance(const Symbol('asPlugin'),
          [new barback.BarbackSettings(configuration, mode)]).reflectee;
    }).where((classMirror) => classMirror != null));
  }

  var library = _mirrors.libraries[uri];
  if (library == null) throw "Couldn't find library at $uri.";

  loadFromLibrary(library);
  return transformers;
}

MethodMirror _getConstructor(ClassMirror classMirror, String constructor) {
  var name = new Symbol("${MirrorSystem.getName(classMirror.simpleName)}"
      ".$constructor");
  var candidate = classMirror.declarations[name];
  if (candidate is MethodMirror && candidate.isConstructor) return candidate;
  return null;
}
