#!/bin/bash

# Fast fail the script on failures.
set -e

e2e_tests () {
  if [ "$TRAVIS" == "true" ]; then
    echo "Installing bazel"
    # Install bazel if we are on travis.
    wget https://github.com/bazelbuild/bazel/releases/download/0.4.4/bazel_0.4.4-linux-x86_64.deb
    sudo dpkg -i bazel_0.4.4-linux-x86_64.deb
  fi

  echo "Running e2e tests"
  pushd e2e_test
  pub upgrade
  pub run test
  popd
}

unit_tests () {
  echo "Running bazel_codegen unit tests"
  pushd bazel_codegen
  pub upgrade
  dartanalyzer --fatal-warnings lib/_bazel_codegen.dart
  pub run test
  popd

  echo "Running dazel unit tests"
  pushd dazel
  pub upgrade
  dartanalyzer --fatal-warnings bin/dazel.dart
  pub run test
  popd
}

if [ -z "$TEST_GROUP" ]; then
  # Run all tests if not specified
  unit_tests
  e2e_tests
else
  if [ "$TEST_GROUP" == "e2e_tests" ]; then
    e2e_tests
  elif [ "$TEST_GROUP" == "unit_tests" ]; then
    unit_tests
  else
    echo "ERROR: Unrecognized TEST_GROUP $TEST_GROUP"
  fi
fi
