#!/bin/bash
# GitHub CLI (gh) 설치 (pre-downloaded binary tarball)
# apt를 우회하여 빠르게 설치

set -eu
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GH_VERSION="2.90.0"
TARBALL="$SCRIPT_DIR/gh_${GH_VERSION}_linux_amd64.tar.gz"
INSTALL_DIR="/usr/local"

SUDO=""
if [[ $EUID -ne 0 ]]; then
    SUDO="sudo"
fi

if [ ! -f "$TARBALL" ]; then
    echo "Error: $TARBALL not found. Falling back to network install."
    $SUDO mkdir -p /etc/apt/keyrings
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | $SUDO tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | $SUDO tee /etc/apt/sources.list.d/github-cli-stable.list > /dev/null
    $SUDO apt update -qq
    $SUDO apt install -y gh
    exit $?
fi

$SUDO tar -xzf "$TARBALL" -C /tmp
$SUDO cp /tmp/gh_${GH_VERSION}_linux_amd64/bin/gh "$INSTALL_DIR/bin/"
$SUDO cp -r /tmp/gh_${GH_VERSION}_linux_amd64/share/ "$INSTALL_DIR/"
$SUDO rm -rf /tmp/gh_${GH_VERSION}_linux_amd64
echo "gh v${GH_VERSION} installed from local tarball"
