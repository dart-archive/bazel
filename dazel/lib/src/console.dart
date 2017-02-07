// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

final _cyan = _isPosixTerminal ? '\u001b[36m' : '';
final _green = _isPosixTerminal ? '\u001b[32m' : '';
final _red = _isPosixTerminal ? '\u001b[31m' : '';
final _yellow = _isPosixTerminal ? '\u001b[33m' : '';
final _endColor = _isPosixTerminal ? '\u001b[0m' : '';
final _isPosixTerminal =
    !Platform.isWindows && stdioType(stdout) == StdioType.TERMINAL;

printCyan(String message) => print(inCyan(message));
printGreen(String message) => print(inGreen(message));
printRed(String message) => print(inRed(message));
printYellow(String message) => print(inYellow(message));

String inCyan(String message) => _inColor(_cyan, message);
String inGreen(String message) => _inColor(_green, message);
String inRed(String message) => _inColor(_red, message);
String inYellow(String message) => _inColor(_yellow, message);

String _inColor(String color, String message) => '$color$message$_endColor';
