#!/bin/bash

# Fast fail the script on failures.
set -e

pushd bazel_codegen
pub upgrade
dartanalyzer --fatal-warnings lib/_bazel_codegen.dart
pub run test
popd

pushd dazel
pub upgrade
dartanalyzer --fatal-warnings bin/dazel.dart
pub run test
popd

pushd e2e_test
pub upgrade
pub run test
popd
