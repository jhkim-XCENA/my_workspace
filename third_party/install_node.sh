#!/bin/bash
# Node.js 22.x 설치 (NodeSource APT 레포 등록 + 설치)
# https://github.com/nodesource/distributions

SUDO=""
if [[ $EUID -ne 0 ]]; then
    SUDO="sudo"
fi

curl -fsSL https://deb.nodesource.com/setup_22.x | $SUDO -E bash -
$SUDO apt install -y nodejs
