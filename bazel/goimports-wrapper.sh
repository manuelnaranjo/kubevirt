#!/bin/bash
#
# This file is part of the KubeVirt project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Copyright 2025 Red Hat, Inc.
#
# Wrapper script for goimports with KubeVirt-specific defaults.
# This replaces the deprecated @com_github_ash2k_bazel_tools//goimports rule.

set -euo pipefail

# Resolve goimports binary path from runfiles
# GOIMPORTS_BIN is set via env attribute in BUILD.bazel
GOIMPORTS=$(realpath "./external/${GOIMPORTS_BIN}")
if [[ ! -x "${GOIMPORTS}" ]]; then
    echo >&2 "ERROR: cannot find goimports binary at ${GOIMPORTS_BIN}"
    exit 1
fi

# Change to the workspace root (where BUILD.bazel is)
cd "${BUILD_WORKSPACE_DIRECTORY:-$(pwd)}"

# Excluded paths (matching the old goimports rule)
EXCLUDE_PATHS=(
    "./vendor"
    "./.history"
    "./.git"
    "./_ci-configs"
)

# Build the find exclusion arguments
FIND_EXCLUDES=""
for path in "${EXCLUDE_PATHS[@]}"; do
    FIND_EXCLUDES="$FIND_EXCLUDES -path $path -prune -o"
done

# Find all .go files excluding vendor and other paths
GO_FILES=$(find . $FIND_EXCLUDES -name "*.go" -print)

if [ -z "$GO_FILES" ]; then
    echo "No Go files found to format"
    exit 0
fi

# Run goimports with:
# -w: write result to file instead of stdout
# -local: put imports beginning with this string after 3rd-party packages
echo "Running goimports..."
echo "$GO_FILES" | xargs "${GOIMPORTS}" -w -local "kubevirt.io/kubevirt"

echo "goimports complete"
