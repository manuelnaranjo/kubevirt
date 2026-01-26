#!/usr/bin/env bash

set -eou pipefail
set -x

LIBVIRT_VERSION=${LIBVIRT_VERSION:-0:10.10.0-13.el9}
QEMU_VERSION=${QEMU_VERSION:-17:9.1.0-20.el9}
SEABIOS_VERSION=${SEABIOS_VERSION:-0:1.16.3-4.el9}
EDK2_VERSION=${EDK2_VERSION:-0:20241117-3.el9}
LIBGUESTFS_VERSION=${LIBGUESTFS_VERSION:-1:1.54.0-9.el9}
GUESTFSTOOLS_VERSION=${GUESTFSTOOLS_VERSION:-0:1.52.2-5.el9}
PASST_VERSION=${PASST_VERSION:-0:0^20250512.g8ec1341-2.el9}
VIRTIOFSD_VERSION=${VIRTIOFSD_VERSION:-0:1.13.0-1.el9}
SWTPM_VERSION=${SWTPM_VERSION:-0:0.8.0-2.el9}
SINGLE_ARCH=${SINGLE_ARCH:-""}
BASESYSTEM=${BASESYSTEM:-"centos-stream-release"}

bazeldnf_repos="--repofile rpm/repo.yaml"
if [ "${CUSTOM_REPO:-}" ]; then
    bazeldnf_repos="--repofile ${CUSTOM_REPO} ${bazeldnf_repos}"
fi

# Packages that we want to be included in all container images.
#
# Further down we define per-image package lists, which just like
# this one are split across multiple variables:
#
#   * $foo_main  => packages that we want to have in the image;
#
#   * $foo_ARCH  => same as above, but specific to one architecture;
#
#   * $foo_extra => (indirect) dependencies that can be satisfied by
#                   more than one package.
#
# Listing the "extra" packages explicitly ensures that bazeldnf will
# always reach the same solution, and thus keeps things reproducible

centos_main="
  acl
  curl-minimal
  vim-minimal
"
centos_extra="
  coreutils-single
  glibc-minimal-langpack
  libcurl-minimal
"

# create a rpmtree for our test image with misc. tools.
testimage_main="
  device-mapper
  e2fsprogs
  iputils
  nmap-ncat
  procps-ng
  qemu-img
  sevctl
  tar
  targetcli
  util-linux
  which
"

# create a rpmtree for libvirt-devel. libvirt-devel is needed for compilation and unit-testing.
libvirtdevel_main="
  libvirt-devel
"
libvirtdevel_extra="
  keyutils-libs
  krb5-libs
  libmount
  lz4-libs
"

# TODO: Remove the sssd-client and use a better sssd config
# This requires a way to inject files into the sandbox via bazeldnf
sandboxroot_main="
  findutils
  gcc
  glibc-static
  python3
  sssd-client
"

# create a rpmtree for virt-launcher and virt-handler. This is the OS for our node-components.
launcherbase_main="
  libvirt-client
  libvirt-daemon-driver-qemu
  passt
  qemu-kvm-core
  qemu-kvm-device-usb-host
  swtpm-tools
"
launcherbase_x86_64="
  edk2-ovmf
  qemu-kvm-device-display-virtio-gpu
  qemu-kvm-device-display-virtio-vga
  qemu-kvm-device-display-virtio-gpu-pci
  qemu-kvm-device-usb-redirect
  seabios
"
launcherbase_aarch64="
  edk2-aarch64
  qemu-kvm-device-usb-redirect
  qemu-kvm-device-display-virtio-gpu
  qemu-kvm-device-display-virtio-gpu-pci
"
launcherbase_s390x="
  qemu-kvm-device-display-virtio-gpu
  qemu-kvm-device-display-virtio-gpu-ccw
"
launcherbase_extra="
  findutils
  nftables
  nmap-ncat
  procps-ng
  selinux-policy
  selinux-policy-targeted
  tar
  virtiofsd
  xorriso
"

handlerbase_main="
  qemu-img
"
handlerbase_extra="
  findutils
  iproute
  nftables
  procps-ng
  selinux-policy
  selinux-policy-targeted
  tar
  util-linux
  xorriso
"

libguestfstools_main="
  libguestfs
  guestfs-tools
  libvirt-daemon-driver-qemu
  qemu-kvm-core
"
libguestfstools_x86_64="
  edk2-ovmf
  seabios
"

libguestfstools_s390x="
  edk2-ovmf
"
libguestfstools_extra="
  selinux-policy
  selinux-policy-targeted
"

exportserverbase_main="
  tar
"

pr_helper="
  qemu-pr-helper
"

sidecar_shim="
    python3
"

# lockfile generates an rpm lockfile for the given packages
# Usage: lockfile <name> <arch> <packages...>
lockfile() {
    local name="$1"
    shift
    local arch="$1"
    shift
    bazel run \
        //:bazeldnf -- lockfile \
        --lockfile "rpm/lock-files/${name}-${arch}.json" \
        --arch "$arch" \
        --nobest \
        --basesystem ${BASESYSTEM} \
        ${bazeldnf_repos} \
        "$@"
}

# get latest repo data from repo.yaml
bazel run \
    //:bazeldnf -- fetch \
    ${bazeldnf_repos}

archs=(x86_64 aarch64 s390x)

for arch in "${archs[@]}"; do
    echo "$arch"

    lockfile centos ${arch} $centos_main $centos_extra

    lockfile test-image ${arch} $testimage_main

    lockfile libvirt ${arch} $libvirtdevel_main $libvirtdevel_extra

    lockfile sandboxroot ${arch} $sandboxroot_main

    varname="launcherbase_${arch}"
    lockfile launcherbase ${arch} $launcherbase_main ${!varname:-} $launcherbase_extra

    lockfile passt ${arch} passt

    varname="libguestfstools_${arch}"
    lockfile libguestfstools ${arch} \
        $libguestfstools_main \
        ${!varname:-} \
        $libguestfstools_extra \
        --force-ignore-with-dependencies '^(kernel-|linux-firmware)' \
        --force-ignore-with-dependencies '^(python[3]{0,1}-)' \
        --force-ignore-with-dependencies '^mozjs60' \
        --force-ignore-with-dependencies '^(libvirt-daemon-kvm|swtpm)' \
        --force-ignore-with-dependencies '^(man-db|mandoc)' \
        --force-ignore-with-dependencies '^dbus'

    lockfile exportserverbase ${arch} $exportserverbase_main

    lockfile pr-helper ${arch} $pr_helper

    lockfile sidecar-shim ${arch} $sidecar_shim

done
