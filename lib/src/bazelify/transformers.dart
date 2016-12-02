// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:mirrors';

import 'package:barback/barback.dart';

/// The mirror system.
///
/// Cached to avoid re-instantiating each time a transformer is initialized.
final _mirrors = currentMirrorSystem();

/// Loads all the transformers and groups defined in [uri].
///
/// Loads the library, finds any [Transformer] or [TransformerGroup] subclasses
/// in it, instantiates them with [configuration] and [mode], and returns them.
List createTransformersInLibrary(
    Uri uri, Map configuration, BarbackMode mode) {
  var transformerClass = reflectClass(Transformer);
  var aggregateClass = reflectClass(AggregateTransformer);
  var groupClass = reflectClass(TransformerGroup);

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

    transformers.addAll(library.declarations.values.map((declaration) {
      if (declaration is! ClassMirror) return null;
      var classMirror = declaration;
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
          [new BarbackSettings(configuration, mode)]).reflectee;
    }).where((classMirror) => classMirror != null));
  }

  var library = _mirrors.libraries[uri];
  if (library == null) {
    throw new ArgumentError("Couldn't find library at $uri.");
  }

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
