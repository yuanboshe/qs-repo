#!/bin/bash

# 安装或升级 Go 到指定版本

# 定义变量
VERSION="1.23.0"
GOROOT="$HOME/.go"
GOPATH="$HOME/go"

print_error() {
  echo "Error: $1" >&2
}

remove_old_go_version() {
  local old_goroot=$1
  if ! rm -rf "$old_goroot"; then
    echo "Failed to remove old Go version. Trying with sudo..."
    if ! sudo rm -rf "$old_goroot"; then
      print_error "Failed to remove old Go version. You may need to remove it manually."
      exit 1
    fi
  fi
}

setup_go() {
  local version="$1"
  local platform="$2"
  local goroot="$3"
  local gopath="$4"

  if command -v go &>/dev/null; then
    local installed_version=$(go version | awk '{print $3}' | sed 's/go//')
    if [[ "$installed_version" == "$version" ]]; then
      echo "Go version $version is already installed."
      return 0
    else
      echo "Uninstalling old version of Go..."
      local old_goroot=$(go env GOROOT)
      remove_old_go_version "$old_goroot"
    fi
  fi

  echo "Downloading Go version $version..."
  local tmp_dir=$(mktemp -d)
  local download_url="https://go.dev/dl/go$version.$platform.tar.gz"
  local download_file="$tmp_dir/go$version.$platform.tar.gz"

  curl -L "$download_url" -o "$download_file" || {
    print_error "Download failed"
    exit 1
  }

  echo "Extracting Go to $goroot..."
  mkdir -p "$goroot" && tar -C "$goroot" --strip-components=1 -xzf "$download_file" || {
    print_error "Extraction failed"
    exit 1
  }

  rm -rf "$tmp_dir"

  echo "Configuring environment variables in .bashrc..."
  local bashrc="$HOME/.bashrc"

  # 删除旧的 Go 配置
  sed -i '/^export GOROOT=/d' "$bashrc"
  sed -i '/^export GOPATH=/d' "$bashrc"
  sed -i '/^\s*export PATH=.*\/go\/bin:/d' "$bashrc"
  sed -i "/^export PATH=\\\$GOROOT\/bin:/d" "$bashrc"
  sed -i "/^export PATH=\\\$GOPATH\/bin:/d" "$bashrc"

  # 添加新的 Go 配置
  {
    echo "export GOROOT=$goroot"
    echo "export GOPATH=$gopath"
    echo "export PATH=\$GOROOT/bin:\$GOPATH/bin:\$PATH"
  } >>"$bashrc"

  source "$bashrc"

  # 执行 go version 命令并检查结果
  if go version &>/dev/null; then
    echo "Go version $version has been successfully installed."
  else
    echo "Failed to install Go version $version. Please check the installation."
  fi
}

main() {
  local version=${1:-"latest"}
  local platform="$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m | sed 's/x86_64/amd64/;s/i[3-6]86/386/')"

  if [[ "$version" == "latest" ]]; then
    version=$(curl -s --retry 5 --retry-delay 1 --max-time 3 https://go.dev/VERSION?m=text | head -n 1 | sed 's/go//')
  fi

  # 检查版本号是否成功获取
  if [[ -z "$version" ]]; then
    echo "无法获取到最新版本号，请重新尝试。"
    exit 1
  fi

  setup_go "$version" "$platform" "$2" "$3"
}

main "$VERSION" "$GOROOT" "$GOPATH"
