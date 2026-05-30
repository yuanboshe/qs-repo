#!/bin/bash

# @description 验证 Docker Engine、Docker Compose 和 daemon 状态；可选运行 hello-world 拉取测试镜像
# @platform linux/ubuntu>=22.04 linux/debian>=12
# @shell bash
# @requires sudo docker
# @effects command-run
# @network docker.io

# @arg 是否运行 docker run --rm hello-world；需要访问 Docker Hub 或已配置可用 mirror
RUN_HELLO_WORLD="false"

set -Eeuo pipefail

docker_verify_log() {
  echo "[docker/verify] $*"
}

docker_verify_need_sudo() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

docker_verify_docker() {
  if docker "$@" >/dev/null 2>&1; then
    docker "$@"
  else
    docker_verify_need_sudo docker "$@"
  fi
}

docker_verify_main() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "未找到 docker 命令" >&2
    exit 1
  fi

  docker_verify_log "Docker version"
  docker_verify_docker version

  docker_verify_log "Docker daemon info"
  docker_verify_docker info

  docker_verify_log "Docker Compose version"
  docker compose version

  if [ "${RUN_HELLO_WORLD}" = "true" ]; then
    docker_verify_log "运行 hello-world 容器"
    docker_verify_docker run --rm hello-world
  else
    docker_verify_log "跳过 hello-world 拉取测试：RUN_HELLO_WORLD=${RUN_HELLO_WORLD}"
  fi

  docker_verify_log "Docker 环境验证完成"
}

docker_verify_main
