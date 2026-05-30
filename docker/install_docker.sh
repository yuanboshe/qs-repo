#!/bin/bash

# @description 通过 Docker 官方 apt 仓库安装 Docker Engine，涉及 sudo、apt 源、系统服务和 docker 用户组变更
# @platform linux/ubuntu>=22.04 linux/debian>=12
# @shell bash
# @requires sudo apt-get curl gnupg lsb-release systemd
# @effects apt-source package-install service-enable service-restart user-group
# @network download.docker.com mirrors.aliyun.com

# @arg Docker apt 仓库地址，auto 根据系统选择官方源；国内 Ubuntu 服务器可覆盖为 https://mirrors.aliyun.com/docker-ce/linux/ubuntu
APT_MIRROR="auto"
# @arg Docker apt 仓库 fallback，多个地址用逗号分隔；{os} 会替换为 ubuntu 或 debian
APT_MIRROR_FALLBACKS="https://mirrors.aliyun.com/docker-ce/linux/{os}"
# @arg apt channel，通常保持 stable
APT_CHANNEL="stable"
# @arg 追加到 docker 组的用户，auto 表示当前 sudo 调用用户；none 表示不修改用户组；多个用户用逗号分隔
DOCKER_USERS="auto"
# @arg 是否启用并启动 docker 服务
ENABLE_SERVICE="true"

set -Eeuo pipefail

docker_install_log() {
  echo "[docker/install] $*"
}

docker_install_need_sudo() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

docker_install_detect_os() {
  if [ ! -r /etc/os-release ]; then
    echo "无法读取 /etc/os-release，当前脚本仅支持 Debian/Ubuntu 系发行版" >&2
    exit 1
  fi

  # shellcheck disable=SC1091
  . /etc/os-release
  case "${ID:-}" in
  ubuntu | debian)
    DOCKER_INSTALL_OS_ID="${ID}"
    DOCKER_INSTALL_OS_CODENAME="${VERSION_CODENAME:-}"
    ;;
  *)
    echo "当前发行版 ${ID:-unknown} 不受支持；请使用 Ubuntu/Debian 或为该系统新增 template" >&2
    exit 1
    ;;
  esac

  if [ -z "${DOCKER_INSTALL_OS_CODENAME}" ]; then
    echo "无法识别系统 codename，不能安全配置 Docker apt 源" >&2
    exit 1
  fi
}

docker_install_arch() {
  case "$(dpkg --print-architecture)" in
  amd64 | arm64 | armhf | s390x | ppc64el)
    dpkg --print-architecture
    ;;
  *)
    echo "Docker 官方 apt 源不支持当前架构：$(dpkg --print-architecture)" >&2
    exit 1
    ;;
  esac
}

docker_install_setup_repo() {
  local arch="$1"
  local keyring="/etc/apt/keyrings/docker.asc"
  local list_file="/etc/apt/sources.list.d/docker.list"

  docker_install_log "安装 apt 依赖"
  docker_install_need_sudo apt-get update
  docker_install_need_sudo apt-get install -y ca-certificates curl gnupg lsb-release

  docker_install_log "配置 Docker apt keyring"
  docker_install_need_sudo install -m 0755 -d /etc/apt/keyrings

  local repo_url
  for repo_url in $(docker_install_repo_candidates); do
    if docker_install_try_repo "${repo_url}" "${arch}" "${keyring}" "${list_file}"; then
      return 0
    fi
  done

  echo "所有 Docker apt 仓库都不可用，请检查网络或覆盖 apt_mirror / apt_mirror_fallbacks" >&2
  exit 1
}

docker_install_normalize_repo_url() {
  local repo_url="$1"
  if [ "${repo_url}" = "auto" ]; then
    repo_url="https://download.docker.com/linux/${DOCKER_INSTALL_OS_ID}"
  fi
  repo_url="${repo_url//\{os\}/${DOCKER_INSTALL_OS_ID}}"
  echo "${repo_url%/}"
}

docker_install_repo_candidates() {
  local candidates="${APT_MIRROR}"
  if [ -n "${APT_MIRROR_FALLBACKS}" ]; then
    candidates="${candidates},${APT_MIRROR_FALLBACKS}"
  fi

  local candidate
  echo "${candidates}" | tr ',' '\n' | while IFS= read -r candidate; do
    candidate="$(echo "${candidate}" | xargs)"
    if [ -n "${candidate}" ]; then
      docker_install_normalize_repo_url "${candidate}"
    fi
  done
}

docker_install_try_repo() {
  local repo_url="$1"
  local arch="$2"
  local keyring="$3"
  local list_file="$4"
  local tmp_keyring

  tmp_keyring="$(mktemp)"

  docker_install_log "尝试 Docker apt 源：${repo_url}"
  if ! curl -fsSL --retry 5 --retry-delay 2 --connect-timeout 10 "${repo_url}/gpg" -o "${tmp_keyring}"; then
    docker_install_log "下载 GPG key 失败，尝试下一个 Docker apt 源"
    rm -f "${tmp_keyring}"
    return 1
  fi

  docker_install_need_sudo install -m 0644 "${tmp_keyring}" "${keyring}"
  rm -f "${tmp_keyring}"
  docker_install_need_sudo chmod a+r "${keyring}"

  docker_install_log "写入 Docker apt 源：${repo_url} ${DOCKER_INSTALL_OS_CODENAME} ${APT_CHANNEL}"
  echo "deb [arch=${arch} signed-by=${keyring}] ${repo_url} ${DOCKER_INSTALL_OS_CODENAME} ${APT_CHANNEL}" |
    docker_install_need_sudo tee "${list_file}" >/dev/null

  if docker_install_need_sudo apt-get update; then
    return 0
  fi

  docker_install_log "apt-get update 失败，尝试下一个 Docker apt 源"
  return 1
}

docker_install_engine() {
  docker_install_log "安装 Docker Engine 与常用插件"
  docker_install_need_sudo apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin
}

docker_install_enable_service() {
  if [ "${ENABLE_SERVICE}" != "true" ]; then
    docker_install_log "跳过 docker 服务启用：ENABLE_SERVICE=${ENABLE_SERVICE}"
    return 0
  fi

  if command -v systemctl >/dev/null 2>&1; then
    docker_install_need_sudo systemctl enable docker
    docker_install_need_sudo systemctl restart docker
  else
    docker_install_need_sudo service docker restart
  fi
}

docker_install_target_users() {
  if [ "${DOCKER_USERS}" = "none" ]; then
    return 0
  fi

  if [ "${DOCKER_USERS}" = "auto" ]; then
    if [ "$(id -u)" -eq 0 ]; then
      if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER}" != "root" ]; then
        echo "${SUDO_USER}"
      fi
    else
      id -un
    fi
    return 0
  fi

  echo "${DOCKER_USERS}" | tr ',' ' '
}

docker_install_configure_group() {
  local users
  users="$(docker_install_target_users)"
  if [ -z "${users}" ]; then
    docker_install_log "没有需要追加到 docker 组的用户"
    return 0
  fi

  docker_install_need_sudo groupadd -f docker
  for user in ${users}; do
    if id "${user}" >/dev/null 2>&1; then
      docker_install_log "追加用户 ${user} 到 docker 组"
      docker_install_need_sudo usermod -aG docker "${user}"
    else
      echo "用户 ${user} 不存在，跳过 docker 组配置" >&2
    fi
  done

  docker_install_log "docker 组权限需要用户重新登录后生效"
}

docker_install_main() {
  docker_install_detect_os

  if command -v docker >/dev/null 2>&1; then
    docker_install_log "检测到已安装 Docker：$(docker --version)"
  fi

  docker_install_setup_repo "$(docker_install_arch)"
  docker_install_engine
  docker_install_enable_service
  docker_install_configure_group

  docker_install_log "Docker Engine 安装完成"
}

docker_install_main
