load("@io_bazel_rules_dart//dart/build_rules:vm.bzl", "dart_vm_binary")

dart_vm_binary(
    name = "get_cwd",
    srcs = ["bin/get_cwd.dart"],
    script_file = "bin/get_cwd.dart",
    deps = [
        "@path//:path",
    ],
)
