#!/bin/bash

# @description 安装 Docker Compose v2 插件，并按需提供兼容旧命令的 docker-compose wrapper
# @platform linux/ubuntu>=22.04 linux/debian>=12
# @shell bash
# @requires sudo apt-get docker
# @effects package-install system-file:/usr/local/bin/docker-compose
# @network download.docker.com mirrors.aliyun.com

# @arg 是否创建 /usr/local/bin/docker-compose 兼容 wrapper
INSTALL_LEGACY_WRAPPER="true"

set -Eeuo pipefail

docker_compose_log() {
  echo "[docker/compose] $*"
}

docker_compose_need_sudo() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

docker_compose_install_plugin() {
  if docker compose version >/dev/null 2>&1; then
    docker_compose_log "Docker Compose plugin 已安装：$(docker compose version --short 2>/dev/null || docker compose version)"
    return 0
  fi

  docker_compose_log "通过 apt 安装 docker-compose-plugin"
  docker_compose_need_sudo apt-get update
  docker_compose_need_sudo apt-get install -y docker-compose-plugin
}

docker_compose_install_wrapper() {
  if [ "${INSTALL_LEGACY_WRAPPER}" != "true" ]; then
    docker_compose_log "跳过 docker-compose 兼容 wrapper"
    return 0
  fi

  if command -v docker-compose >/dev/null 2>&1; then
    docker_compose_log "检测到已有 docker-compose：$(docker-compose version --short 2>/dev/null || docker-compose version)"
    return 0
  fi

  docker_compose_log "创建 /usr/local/bin/docker-compose 兼容 wrapper"
  cat <<'EOF' | docker_compose_need_sudo tee /usr/local/bin/docker-compose >/dev/null
#!/bin/sh
exec docker compose "$@"
EOF
  docker_compose_need_sudo chmod 0755 /usr/local/bin/docker-compose
}

docker_compose_main() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "未找到 docker 命令，请先执行 docker/install_docker.sh" >&2
    exit 1
  fi

  docker_compose_install_plugin
  docker_compose_install_wrapper
  docker_compose_log "Docker Compose 安装完成"
}

docker_compose_main
