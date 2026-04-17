#!/bin/bash
# Node.js 설치 (pre-downloaded binary tarball)
# apt를 우회하여 빠르게 설치

set -eu
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

NODE_VERSION="22.22.2"
TARBALL="$SCRIPT_DIR/node-v${NODE_VERSION}-linux-x64.tar.xz"
INSTALL_DIR="/usr/local"

SUDO=""
if [[ $EUID -ne 0 ]]; then
    SUDO="sudo"
fi

if [ ! -f "$TARBALL" ]; then
    echo "Error: $TARBALL not found. Falling back to network install."
    curl -fsSL https://deb.nodesource.com/setup_22.x | $SUDO -E bash -
    $SUDO apt install -y nodejs
    exit $?
fi

$SUDO tar -xJf "$TARBALL" -C "$INSTALL_DIR" --strip-components=1
echo "Node.js v${NODE_VERSION} installed from local tarball"
