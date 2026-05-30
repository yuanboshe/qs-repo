#!/bin/bash

# @description 写入 /etc/docker/daemon.json，配置日志轮转、live-restore 和可选 registry mirror；会备份旧配置并重启 docker
# @platform linux/ubuntu>=22.04 linux/debian>=12
# @shell bash
# @requires sudo docker systemd
# @effects system-file:/etc/docker/daemon.json backup-file service-restart

# @arg Docker registry mirrors，多个地址用逗号分隔；空值表示不配置 mirror
REGISTRY_MIRRORS=""
# @arg Docker json-file 日志单文件最大大小
LOG_MAX_SIZE="100m"
# @arg Docker json-file 日志保留文件数
LOG_MAX_FILE="3"
# @arg 是否启用 Docker live-restore
LIVE_RESTORE="true"
# @arg 写入配置后是否重启 Docker
RESTART_DOCKER="true"

set -Eeuo pipefail

docker_daemon_log() {
  echo "[docker/daemon] $*"
}

docker_daemon_need_sudo() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

docker_daemon_bool() {
  case "$1" in
  true | false)
    echo "$1"
    ;;
  *)
    echo "$2 必须是 true 或 false，当前值：$1" >&2
    exit 1
    ;;
  esac
}

docker_daemon_registry_mirrors_json() {
  local mirrors="$1"
  local output=""
  local mirror

  mirrors="$(echo "${mirrors}" | xargs)"
  if [ -z "${mirrors}" ]; then
    return 0
  fi

  IFS=',' read -ra mirror_list <<<"${mirrors}"
  for mirror in "${mirror_list[@]}"; do
    mirror="$(echo "${mirror}" | xargs)"
    if [ -z "${mirror}" ]; then
      continue
    fi
    case "${mirror}" in
    *\"*)
      echo "registry mirror 不能包含双引号：${mirror}" >&2
      exit 1
      ;;
    esac
    if [ -n "${output}" ]; then
      output="${output}, "
    fi
    output="${output}\"${mirror}\""
  done

  if [ -n "${output}" ]; then
    echo "  \"registry-mirrors\": [${output}],"
  fi
}

docker_daemon_write_config() {
  local daemon_dir="/etc/docker"
  local daemon_file="${daemon_dir}/daemon.json"
  local tmp_file
  local live_restore

  live_restore="$(docker_daemon_bool "${LIVE_RESTORE}" "LIVE_RESTORE")"
  tmp_file="$(mktemp)"

  {
    echo "{"
    docker_daemon_registry_mirrors_json "${REGISTRY_MIRRORS}"
    echo "  \"log-driver\": \"json-file\","
    echo "  \"log-opts\": {"
    echo "    \"max-size\": \"${LOG_MAX_SIZE}\","
    echo "    \"max-file\": \"${LOG_MAX_FILE}\""
    echo "  },"
    echo "  \"live-restore\": ${live_restore}"
    echo "}"
  } >"${tmp_file}"

  docker_daemon_need_sudo install -d -m 0755 "${daemon_dir}"
  if docker_daemon_need_sudo test -f "${daemon_file}"; then
    local backup="${daemon_file}.bak.$(date +%Y%m%d%H%M%S)"
    docker_daemon_log "备份已有 daemon.json 到 ${backup}"
    docker_daemon_need_sudo cp "${daemon_file}" "${backup}"
  fi

  docker_daemon_log "写入 ${daemon_file}"
  docker_daemon_need_sudo install -m 0644 "${tmp_file}" "${daemon_file}"
  rm -f "${tmp_file}"
}

docker_daemon_restart() {
  if [ "${RESTART_DOCKER}" != "true" ]; then
    docker_daemon_log "跳过 Docker 重启：RESTART_DOCKER=${RESTART_DOCKER}"
    return 0
  fi

  if command -v systemctl >/dev/null 2>&1; then
    docker_daemon_need_sudo systemctl restart docker
  else
    docker_daemon_need_sudo service docker restart
  fi
}

docker_daemon_main() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "未找到 docker 命令，请先执行 docker/install_docker.sh" >&2
    exit 1
  fi

  docker_daemon_write_config
  docker_daemon_restart
  docker_daemon_log "Docker daemon 配置完成"
}

docker_daemon_main
