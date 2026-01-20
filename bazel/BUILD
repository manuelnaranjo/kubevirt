load("@rules_shell//shell:sh_binary.bzl", "sh_binary")

# goimports wrapper - replaces deprecated @com_github_ash2k_bazel_tools//goimports
# Uses goimports from golang.org/x/tools/cmd/goimports (added to go.mod tools)
sh_binary(
    name = "goimports",
    srcs = ["goimports-wrapper.sh"],
    data = ["@org_golang_x_tools//cmd/goimports"],
    env = {
        "GOIMPORTS_BIN": "$(rlocationpath @org_golang_x_tools//cmd/goimports)",
    },
    visibility = ["//visibility:public"],
)
