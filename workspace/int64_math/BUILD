load("@io_bazel_rules_dart//dart/build_rules:vm.bzl", "dart_vm_binary")
load("@io_bazel_rules_dart//dart/build_rules:web.bzl", "dart_web_application")

dart_vm_binary(
    name = "ng2_app_run",
    srcs = ["bin/ng2_app_run.dart"],
    script_file = "bin/ng2_app_run.dart",
    data = [
        ":ng2_app",
        "web/index.html",
    ],
    deps = [
        "@fixnum//:fixnum",
    ],
)

dart_web_application(
    name = "ng2_app",
    srcs = glob(["web/**"]),
    script_file = "web/main.dart",
    deps = [
        "@angular2//:angular2",
    ],
)
