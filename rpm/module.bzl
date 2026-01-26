"""rpm support helper modules

This file defines the list of RPMs available in "all" architectures, also
allows to add extra RPMs per processor architecture if needed and the list of
excludes in the case those are needed for the lock files

It also provides helper methods that provide the targets that keep updated
the <arch>.MODULE.bazel
"""

load("@bazel_lib//lib:utils.bzl", "utils")
load("@bazel_lib//lib:write_source_files.bzl", "write_source_files")
load("@bazel_skylib//rules:write_file.bzl", "write_file")
load("@bazeldnf//bazeldnf:defs.bzl", "rpmtree")


CONFIG = {
    "centos": {
        "all": [
            "acl",
            "curl-minimal",
            "vim-minimal",
            "coreutils-single",
            "glibc-minimal-langpack",
            "libcurl-minimal",
        ],
    },
    "testimage": {
        "all": [
            "device-mapper",
            "e2fsprogs",
            "iputils",
            "nmap-ncat",
            "procps-ng",
            "qemu-img",
            "sevctl",
            "tar",
            "targetcli",
            "util-linux",
            "which",
        ],
    },
    "libvirt": {
        "all": [
            "libvirt-devel",
            "keyutils-libs",
            "krb5-libs",
            "libmount",
            "lz4-libs",
        ],
    },
    "sandboxroot": {
        "all": [
            "findutils",
            "gcc",
            "glibc-static",
            "python3",
            "sssd-client",
        ],
    },
    "launcherbase": {
        "all": [
            "libvirt-client",
            "libvirt-daemon-driver-qemu",
            "passt",
            "qemu-kvm-core",
            "qemu-kvm-device-usb-host",
            "swtpm-tools",
            "findutils",
            "nftables",
            "nmap-ncat",
            "procps-ng",
            "selinux-policy",
            "selinux-policy-targeted",
            "tar",
            "virtiofsd",
            "xorriso",
        ],
        "x86-64": [
            "edk2-ovmf",
            "qemu-kvm-device-display-virtio-gpu",
            "qemu-kvm-device-display-virtio-vga",
            "qemu-kvm-device-display-virtio-gpu-pci",
            "qemu-kvm-device-usb-redirect",
            "seabios",
        ],
        "aarch64": [
            "edk2-aarch64",
            "qemu-kvm-device-usb-redirect",
            "qemu-kvm-device-display-virtio-gpu",
            "qemu-kvm-device-display-virtio-gpu-pci",
        ],
        "s390x": [
            "qemu-kvm-device-display-virtio-gpu",
            "qemu-kvm-device-display-virtio-gpu-ccw",
        ],
    },
    "handlerbase": {
        "all": [
            "qemu-img",
            "findutils",
            "iproute",
            "nftables",
            "procps-ng",
            "selinux-policy",
            "selinux-policy-targeted",
            "tar",
            "util-linux",
            "xorriso",
        ],
    },
    "libguestfstools": {
        "all": [
            "libguestfs",
            "guestfs-tools",
            "libvirt-daemon-driver-qemu",
            "qemu-kvm-core",
            "selinux-policy",
            "selinux-policy-targeted",
        ],
        "exclude": [
            "^(kernel-|linux-firmware)",
            "^(python[3]{0,1}-)",
            "^mozjs60",
            "^(libvirt-daemon-kvm|swtpm)",
            "^(man-db|mandoc)",
            "^dbus",
        ],
        "x86-64": [
            "edk2-ovmf",
            "seabios",
        ],
        "s390x": [
            "edk2-ovmf",
        ],
    },
    "exportserverbase": {
        "all": [
            "tar",
        ],
    },
    "pr-helper": {
        "all": [
            "qemu-pr-helper",
        ],
    },
    "sidecar-shim": {
        "all": [
            "python3",
        ],
    },
    "passt": {
        "all": [
            "passt",
        ],
    },
}

_MODULE_BAZEL_TEMPLATE = 'bazeldnf = use_extension("@bazeldnf//bazeldnf:extensions.bzl", "bazeldnf")'

_CONFIG_TEMPLATE = """
bazeldnf.config(
    name = "bazeldnf-{name}-{arch}",
    lock_file = "//rpm/lock-files:{name}-{arch}.json",
    nobest = True,
    repofile = "//rpm:repo.yaml",
    rpms = [ {rpms} ],
    rpm_repository_prefix = "bazeldnf-{arch}",
    excludes = [ {excludes} ],
    architectures = [ "{arch}" ],
)

"""

def _stringify_array(inp):
    return ", ".join(['"{}"'.format(x) for x in inp])

def generate_module_file(name, arch):
    """Creates a bazel target to manage the content of a <arch>.MODULE.bazel

    Args:
        name: name of the target that will be generated
        arch: target CPU architecture
    """
    out = [_MODULE_BAZEL_TEMPLATE]
    repos = []

    for repo_name, config in CONFIG.items():
        rpms = config["all"] + config.get(arch, [])
        rpms = _stringify_array(rpms)
        excludes = config.get("exclude", [])
        excludes = _stringify_array(excludes)

        out.append(
            _CONFIG_TEMPLATE.format(
                name = repo_name,
                arch = arch,
                rpms = rpms,
                excludes = excludes,
            ),
        )

        repos.append("bazeldnf-{}-{}".format(repo_name, arch))

    out.append("use_repo(\nbazeldnf, \n{})".format(_stringify_array(repos)))

    write_file(
        name = "{}-module-bazel-dirty".format(name),
        out = "{}.MODULE.bazel.dirty".format(name),
        content = out,
        visibility = ["//visibility:private"]
    )

    native.genrule(
        name = "{}-module-bazel".format(name),
        srcs = ["{}.MODULE.bazel.dirty".format(name)],
        outs = ["{}.MODULE.bazel.tmpl".format(name)],
        tools = [ "@buildifier_prebuilt//buildifier"],
        cmd = "$(location @buildifier_prebuilt//buildifier) -mode fix <$< >$@",
        visibility = ["//visibility:private"],
    )

    write_source_files(
        name = name,
        files = {
            "{}.MODULE.bazel".format(arch): ":{}.MODULE.bazel.tmpl".format(name),
        },
    )

def build_rpmtree(name, archs, configs, symlinks = {}, **kwargs):
    '''Creates an rpmtree target from a given configs for the given archs

    Args:
        name: default target name prefix
        archs: target architectures
        configs: list of configs to use
        symlinks: dictionary of symlinks to pass to rpmtree
        **kwargs: extra arguments to pass to rpmtree
    '''

    for arch in archs:
        target_name = "{}-{}".format(name, arch)
        rpms = []

        for config in configs:
            to_add = CONFIG[config]["all"] + CONFIG[config].get(arch, [])
            rpms.extend([
                "@bazeldnf-{}-{}//{}".format(config, arch, x) for x in to_add
            ])

        rpmtree(
            name = target_name,
            rpms = rpms,
            symlinks = symlinks,
            **utils.propagate_common_rule_attributes(kwargs)
        )
