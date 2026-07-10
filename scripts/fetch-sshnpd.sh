#!/usr/bin/env bash
# Download the sshnpd binary from the NoPorts GitHub releases and stage it
# in build/ for packaging.
#
# Usage: ./scripts/fetch-sshnpd.sh [version]
#   version: e.g. v5.15.1 | latest (default: contents of SSHNPD_VERSION)
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p build

VERSION="${1:-$(cat SSHNPD_VERSION)}"
# Catalyst 9000 and Catalyst 8000 app-hosting CPUs are x86_64.
# (ARM platforms such as IE3400 would need ARCH=arm64 and an arm64 image.)
ARCH="${ARCH:-x64}"
TARBALL="sshnp-linux-${ARCH}.tgz"

if [ "$VERSION" = "latest" ]; then
    URL="https://github.com/atsign-foundation/noports/releases/latest/download/${TARBALL}"
else
    URL="https://github.com/atsign-foundation/noports/releases/download/${VERSION}/${TARBALL}"
fi

echo "Fetching ${URL}"
curl -fsSL -o "build/${TARBALL}" "$URL"

tar -xzf "build/${TARBALL}" -C build
# The tarball extracts to a directory (historically 'sshnp/') containing the
# binaries; locate the ones we package wherever they landed.
for BIN in sshnpd at_activate; do
    BIN_PATH=$(find build -type f -name "$BIN" -not -path "build/$BIN" | head -n1)
    if [ -z "$BIN_PATH" ]; then
        echo "$BIN binary not found in ${TARBALL}" >&2
        exit 1
    fi
    cp "$BIN_PATH" "build/$BIN"
    chmod 0755 "build/$BIN"
    echo "Staged $BIN ${VERSION} at build/$BIN"
done
