load("@io_bazel_rules_dart//dart/build_rules:vm.bzl", "dart_vm_binary")
load("@io_bazel_rules_dart//dart/build_rules:web.bzl", "dart_web_application")

dart_vm_binary(
    name = "get_cwd",
    srcs = ["bin/get_cwd.dart"],
    script_file = "bin/get_cwd.dart",
    deps = [
        "@path//:path",
    ],
)
