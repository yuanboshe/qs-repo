#!/bin/bash
# 安装keychain
if ! command -v keychain &>/dev/null; then
  echo "Installing keychain ..."
  sudo apt-get install -y keychain

  # shellcheck disable=SC2016
  echo 'eval $(keychain --eval --agents ssh)' | tee -a "$HOME/.bashrc"
fi
