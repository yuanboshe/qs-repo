#!/bin/bash

# @description 安装 docker-compose

if ! command -v docker-compose &>/dev/null; then
  echo "Installing docker-compose..."
  # 使用 curl 下载 docker-compose
  curl -L "${GH_PROXY}https://github.com/docker/compose/releases/download/v2.23.1/docker-compose-linux-$(uname -m)" -o /usr/bin/docker-compose || {
    echo "Failed to download docker-compose. Please check your network connection or the URL."
    exit 1
  }
  # 设置执行权限
  sudo chmod +x /usr/bin/docker-compose

  printLine
else
  echo "Docker-compose is already installed."
fi
