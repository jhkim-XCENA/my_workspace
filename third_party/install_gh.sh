#!/bin/bash
# GitHub CLI (gh) 설치 (공식 APT 레포 등록 + 설치)
# https://github.com/cli/cli/blob/trunk/docs/install_linux.md

SUDO=""
if [[ $EUID -ne 0 ]]; then
    SUDO="sudo"
fi

$SUDO mkdir -p /etc/apt/keyrings
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | $SUDO tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | $SUDO tee /etc/apt/sources.list.d/github-cli-stable.list > /dev/null
$SUDO apt update -qq
$SUDO apt install -y gh
