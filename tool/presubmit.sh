#!/bin/bash

# Fast fail the script on failures.
set -e

e2e_tests () {
  echo "Running e2e tests"
  pushd e2e_test
  pub upgrade
  pub run test
  popd
}

unit_tests () {
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
