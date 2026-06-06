#!/bin/bash

# @description 配置 /etc/docker/daemon.json 的日志、live-restore 和 Docker Hub mirror；会备份、重启验证，失败自动回滚
# @platform linux/ubuntu>=20.04 linux/debian>=11
# @shell bash
# @requires sudo curl python3 sort docker systemctl
# @effects network-probe system-file:/etc/docker/daemon.json backup-file service-restart docker-pull
# @network docker.io docker.xuanyuan.me docker.1ms.run docker.1panel.live docker.m.daocloud.io hub.rat.dev dockerproxy.net

# @arg Docker registry mirrors；auto 表示先测 Docker Hub 直连，再仅在 mirror 明显更快或直连失败时写入最快源；none 或空值表示移除 registry-mirrors；也可填逗号分隔的固定 mirror
REGISTRY_MIRRORS="auto"
# @arg Docker json-file 日志单文件最大大小
LOG_MAX_SIZE="100m"
# @arg Docker json-file 日志保留文件数
LOG_MAX_FILE="3"
# @arg 是否启用 Docker live-restore
LIVE_RESTORE="true"
# @arg 写入配置后是否重启 Docker 并验证
RESTART_DOCKER="true"
# @arg Docker Hub mirror 候选池，多个地址可用逗号、空白或换行分隔；最终是否写入以目标主机实时测速为准
MIRROR_CANDIDATES="https://docker.xuanyuan.me,https://docker.1ms.run,https://docker.1panel.live,https://docker.m.daocloud.io,https://hub.rat.dev,https://dockerproxy.net"
# @arg auto 模式下 mirror 至少比 Docker Hub 直连快多少百分比才写入；0 表示只要更快就写入
MIRROR_MIN_SPEEDUP_PERCENT="20"
# @arg 更新后用于 docker pull 验证的镜像；none 表示跳过 pull 验证
MIRROR_VERIFY_IMAGE="hello-world"
# @arg 非交互确认；QS 自动部署时可在 recipe 中覆盖为 true
MIRROR_AUTO_YES="false"

set -Eeuo pipefail

MIRROR_CANDIDATE_FILE=""
MIRROR_REMOTE_URL=""
MIRROR_TOP="3"
MIRROR_ROUNDS="3"
MIRROR_CONNECT_TIMEOUT="3"
MIRROR_MAX_TIME="10"
MIRROR_TEST_IMAGE="alpine"
MIRROR_DRY_RUN="false"
MIRROR_DIRECT_REGISTRY="https://registry-1.docker.io"

declare -a DOCKER_DAEMON_POSITIONAL_CANDIDATES=()
declare -a DOCKER_DAEMON_CANDIDATES=()
declare -a DOCKER_DAEMON_OK_RESULTS=()
declare -a DOCKER_DAEMON_SELECTED_MIRRORS=()

DOCKER_DAEMON_FILE="/etc/docker/daemon.json"
DOCKER_DAEMON_BACKUP_DIR="/etc/docker/daemon-backup"
DOCKER_DAEMON_BACKUP_FILE=""
DOCKER_DAEMON_HAD_FILE="false"
DOCKER_DAEMON_LAST_TIME=""
DOCKER_DAEMON_LAST_REASON=""
DOCKER_DAEMON_LAST_CLASS=""
DOCKER_DAEMON_DIRECT_OK="false"
DOCKER_DAEMON_DIRECT_TIME=""
DOCKER_DAEMON_EFFECTIVE_MIRROR_MODE=""
DOCKER_DAEMON_DOCKER_USE_SUDO="false"
DOCKER_DAEMON_SELF_TEST="false"
DOCKER_DAEMON_SHOW_HELP="false"

docker_daemon_log() {
  echo "[docker/daemon] $*"
}

docker_daemon_warn() {
  echo "[docker/daemon] WARN: $*" >&2
}

docker_daemon_die() {
  echo "[docker/daemon] ERROR: $*" >&2
  exit 1
}

docker_daemon_usage() {
  cat <<'EOF'
Usage:
  configure_docker_daemon.sh [options] [mirror...]

QS template parameters are intentionally small: registry mirrors, log rotation,
live-restore, restart behavior, verify image, and non-interactive confirmation.
The options below are for manual diagnosis or one-off agent runs.

Options:
  --candidate-file FILE       read local candidate mirror list
  --remote-url URL            read remote candidate mirror list
  --top N                     select fastest top N mirrors, default 3
  --rounds N                  probe rounds for each mirror, default 3
  --min-speedup-percent N     mirror must be at least N% faster than direct Docker Hub, default 20
  --connect-timeout SECONDS   curl connect timeout, default 3
  --max-time SECONDS          curl max time, default 10
  --test-image IMAGE          manifest test image, default alpine
  --verify-image IMAGE        docker pull verify image, default hello-world; use none to skip pull verify
  --dry-run                   probe and print results only
  --yes                       apply without interactive confirmation
  --self-test                 run parser/json self-test without root or network
  --help                      show this help

Examples:
  sudo ./docker/configure_docker_daemon.sh --dry-run
  sudo ./docker/configure_docker_daemon.sh --yes
  sudo ./docker/configure_docker_daemon.sh --candidate-file ./mirror_candidates.txt --top 3 --rounds 3 --yes
EOF
}

docker_daemon_python() {
  local py_file rc
  py_file="$(mktemp)"
  cat >"${py_file}"
  set +e
  python3 "${py_file}" "$@"
  rc=$?
  set -e
  rm -f "${py_file}"
  return "${rc}"
}

docker_daemon_as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo -n "$@"
  fi
}

docker_daemon_require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    docker_daemon_die "缺少依赖命令：${cmd}"
  fi
}

docker_daemon_require_root_access() {
  if [ "$(id -u)" -eq 0 ]; then
    return 0
  fi
  docker_daemon_require_cmd sudo
  if ! sudo -n true >/dev/null 2>&1; then
    docker_daemon_die "需要 root 权限；请使用 sudo 运行，或预先配置无交互 sudo。脚本不会等待 sudo 密码输入"
  fi
}

docker_daemon_parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
    --candidate-file)
      [ "$#" -ge 2 ] || docker_daemon_die "--candidate-file 需要参数"
      MIRROR_CANDIDATE_FILE="$2"
      shift 2
      ;;
    --remote-url)
      [ "$#" -ge 2 ] || docker_daemon_die "--remote-url 需要参数"
      MIRROR_REMOTE_URL="$2"
      shift 2
      ;;
    --top)
      [ "$#" -ge 2 ] || docker_daemon_die "--top 需要参数"
      MIRROR_TOP="$2"
      shift 2
      ;;
    --rounds)
      [ "$#" -ge 2 ] || docker_daemon_die "--rounds 需要参数"
      MIRROR_ROUNDS="$2"
      shift 2
      ;;
    --min-speedup-percent)
      [ "$#" -ge 2 ] || docker_daemon_die "--min-speedup-percent 需要参数"
      MIRROR_MIN_SPEEDUP_PERCENT="$2"
      shift 2
      ;;
    --connect-timeout)
      [ "$#" -ge 2 ] || docker_daemon_die "--connect-timeout 需要参数"
      MIRROR_CONNECT_TIMEOUT="$2"
      shift 2
      ;;
    --max-time)
      [ "$#" -ge 2 ] || docker_daemon_die "--max-time 需要参数"
      MIRROR_MAX_TIME="$2"
      shift 2
      ;;
    --test-image)
      [ "$#" -ge 2 ] || docker_daemon_die "--test-image 需要参数"
      MIRROR_TEST_IMAGE="$2"
      shift 2
      ;;
    --verify-image)
      [ "$#" -ge 2 ] || docker_daemon_die "--verify-image 需要参数"
      MIRROR_VERIFY_IMAGE="$2"
      shift 2
      ;;
    --dry-run)
      MIRROR_DRY_RUN="true"
      shift
      ;;
    --yes)
      MIRROR_AUTO_YES="true"
      shift
      ;;
    --self-test)
      DOCKER_DAEMON_SELF_TEST="true"
      shift
      ;;
    --help | -h)
      DOCKER_DAEMON_SHOW_HELP="true"
      shift
      ;;
    --)
      shift
      while [ "$#" -gt 0 ]; do
        DOCKER_DAEMON_POSITIONAL_CANDIDATES+=("$1")
        shift
      done
      ;;
    -*)
      docker_daemon_die "未知参数：$1"
      ;;
    *)
      DOCKER_DAEMON_POSITIONAL_CANDIDATES+=("$1")
      shift
      ;;
    esac
  done
}

docker_daemon_validate_positive_int() {
  local name="$1"
  local value="$2"
  if ! [[ "${value}" =~ ^[1-9][0-9]*$ ]]; then
    docker_daemon_die "${name} 必须是正整数，当前值：${value}"
  fi
}

docker_daemon_validate_positive_number() {
  local name="$1"
  local value="$2"
  if ! [[ "${value}" =~ ^[0-9]+([.][0-9]+)?$ ]] || [ "${value}" = "0" ]; then
    docker_daemon_die "${name} 必须是正数，当前值：${value}"
  fi
}

docker_daemon_validate_nonnegative_number() {
  local name="$1"
  local value="$2"
  if ! [[ "${value}" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    docker_daemon_die "${name} 必须是非负数，当前值：${value}"
  fi
}

docker_daemon_validate_bool() {
  local name="$1"
  local value="$2"
  case "${value}" in
  true | false) ;;
  *) docker_daemon_die "${name} 必须是 true 或 false，当前值：${value}" ;;
  esac
}

docker_daemon_validate_args() {
  docker_daemon_validate_bool "LIVE_RESTORE" "${LIVE_RESTORE}"
  docker_daemon_validate_bool "RESTART_DOCKER" "${RESTART_DOCKER}"
  docker_daemon_validate_bool "MIRROR_DRY_RUN" "${MIRROR_DRY_RUN}"
  docker_daemon_validate_bool "MIRROR_AUTO_YES" "${MIRROR_AUTO_YES}"
  docker_daemon_validate_positive_int "MIRROR_TOP" "${MIRROR_TOP}"
  docker_daemon_validate_positive_int "MIRROR_ROUNDS" "${MIRROR_ROUNDS}"
  docker_daemon_validate_positive_number "MIRROR_CONNECT_TIMEOUT" "${MIRROR_CONNECT_TIMEOUT}"
  docker_daemon_validate_positive_number "MIRROR_MAX_TIME" "${MIRROR_MAX_TIME}"
  docker_daemon_validate_nonnegative_number "MIRROR_MIN_SPEEDUP_PERCENT" "${MIRROR_MIN_SPEEDUP_PERCENT}"
}

docker_daemon_mirror_mode() {
  local value
  value="$(echo "${REGISTRY_MIRRORS}" | xargs)"
  case "${value}" in
  auto) echo "auto" ;;
  "" | none) echo "remove" ;;
  *) echo "static" ;;
  esac
}

docker_daemon_require_dependencies() {
  local mode="$1"
  docker_daemon_require_cmd bash
  docker_daemon_require_cmd python3

  if [ "${mode}" = "auto" ]; then
    docker_daemon_require_cmd curl
    docker_daemon_require_cmd sort
  fi

  if [ "${MIRROR_DRY_RUN}" != "true" ]; then
    docker_daemon_require_root_access
    if [ "${RESTART_DOCKER}" = "true" ]; then
      docker_daemon_require_cmd docker
      docker_daemon_require_cmd systemctl
    fi
  fi
}

docker_daemon_append_candidate_text() {
  local text="$1"
  local output_file="$2"
  if [ -n "${text}" ]; then
    printf '%s\n' "${text}" >>"${output_file}"
  fi
}

docker_daemon_normalize_candidates_file() {
  local input_file="$1"
  docker_daemon_python "${input_file}" <<'PY'
import re
import sys

path = sys.argv[1]
seen = set()

with open(path, "r", encoding="utf-8") as f:
    for raw in f:
        raw = raw.split("#", 1)[0].strip()
        if not raw:
            continue
        for item in re.split(r"[\s,]+", raw):
            item = item.strip().rstrip("/")
            if not item or not re.match(r"^https?://", item):
                continue
            if item in seen:
                continue
            seen.add(item)
            print(item)
PY
}

docker_daemon_static_mirrors() {
  local raw_file
  raw_file="$(mktemp)"
  docker_daemon_append_candidate_text "${REGISTRY_MIRRORS}" "${raw_file}"
  mapfile -t DOCKER_DAEMON_SELECTED_MIRRORS < <(docker_daemon_normalize_candidates_file "${raw_file}" | tr -d '\r')
  rm -f "${raw_file}"

  if [ "${#DOCKER_DAEMON_SELECTED_MIRRORS[@]}" -eq 0 ]; then
    docker_daemon_die "REGISTRY_MIRRORS 未包含合法 http:// 或 https:// mirror"
  fi

  docker_daemon_log "使用固定 registry mirror："
  local index=0 mirror
  for mirror in "${DOCKER_DAEMON_SELECTED_MIRRORS[@]}"; do
    index=$((index + 1))
    printf '%d. %s\n' "${index}" "${mirror}"
  done
}

docker_daemon_collect_candidates() {
  local raw_file candidate remote_text
  raw_file="$(mktemp)"
  docker_daemon_append_candidate_text "${MIRROR_CANDIDATES}" "${raw_file}"

  if [ -n "${MIRROR_CANDIDATE_FILE}" ]; then
    [ -r "${MIRROR_CANDIDATE_FILE}" ] || docker_daemon_die "候选源文件不可读：${MIRROR_CANDIDATE_FILE}"
    cat "${MIRROR_CANDIDATE_FILE}" >>"${raw_file}"
  fi

  if [ -n "${MIRROR_REMOTE_URL}" ]; then
    if remote_text="$(curl -fsSL --connect-timeout "${MIRROR_CONNECT_TIMEOUT}" --max-time "${MIRROR_MAX_TIME}" "${MIRROR_REMOTE_URL}")"; then
      docker_daemon_append_candidate_text "${remote_text}" "${raw_file}"
    else
      docker_daemon_warn "远程候选源读取失败，继续使用本地候选池：${MIRROR_REMOTE_URL}"
    fi
  fi

  for candidate in "${DOCKER_DAEMON_POSITIONAL_CANDIDATES[@]}"; do
    docker_daemon_append_candidate_text "${candidate}" "${raw_file}"
  done

  mapfile -t DOCKER_DAEMON_CANDIDATES < <(docker_daemon_normalize_candidates_file "${raw_file}" | tr -d '\r')
  rm -f "${raw_file}"
  [ "${#DOCKER_DAEMON_CANDIDATES[@]}" -gt 0 ] || docker_daemon_die "没有可用候选源；候选源必须是 http:// 或 https:// URL"
  docker_daemon_log "候选源数量：${#DOCKER_DAEMON_CANDIDATES[@]}"
}

docker_daemon_classify_curl_error() {
  local rc="$1"
  local err="$2"
  local lower_err="${err,,}"
  case "${rc}" in
  28)
    DOCKER_DAEMON_LAST_CLASS="timeout"
    DOCKER_DAEMON_LAST_REASON="timeout"
    ;;
  7)
    DOCKER_DAEMON_LAST_CLASS="connection-refused"
    DOCKER_DAEMON_LAST_REASON="connection refused"
    ;;
  35 | 51 | 58 | 60)
    DOCKER_DAEMON_LAST_CLASS="tls"
    DOCKER_DAEMON_LAST_REASON="tls error"
    ;;
  *)
    case "${lower_err}" in
    *timed\ out* | *timeout*)
      DOCKER_DAEMON_LAST_CLASS="timeout"
      DOCKER_DAEMON_LAST_REASON="timeout"
      ;;
    *refused*)
      DOCKER_DAEMON_LAST_CLASS="connection-refused"
      DOCKER_DAEMON_LAST_REASON="connection refused"
      ;;
    *ssl* | *tls* | *certificate*)
      DOCKER_DAEMON_LAST_CLASS="tls"
      DOCKER_DAEMON_LAST_REASON="tls error"
      ;;
    *)
      DOCKER_DAEMON_LAST_CLASS="curl"
      DOCKER_DAEMON_LAST_REASON="curl rc=${rc}: ${err}"
      ;;
    esac
    ;;
  esac
}

docker_daemon_status_allowed() {
  local status="$1"
  local allowed="$2"
  local code
  for code in ${allowed}; do
    [ "${status}" = "${code}" ] && return 0
  done
  return 1
}

docker_daemon_request() {
  local url="$1"
  local allowed_status="$2"
  local err_file output rc status total_time
  err_file="$(mktemp)"

  set +e
  output="$(curl -sS -L \
    -H 'Accept: application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.manifest.v1+json, */*' \
    --connect-timeout "${MIRROR_CONNECT_TIMEOUT}" \
    --max-time "${MIRROR_MAX_TIME}" \
    -o /dev/null \
    -w '%{http_code} %{time_total}' \
    "${url}" 2>"${err_file}")"
  rc=$?
  set -e

  if [ "${rc}" -ne 0 ]; then
    docker_daemon_classify_curl_error "${rc}" "$(cat "${err_file}")"
    rm -f "${err_file}"
    return 1
  fi
  rm -f "${err_file}"

  status="${output%% *}"
  total_time="${output##* }"
  if ! docker_daemon_status_allowed "${status}" "${allowed_status}"; then
    DOCKER_DAEMON_LAST_REASON="http ${status}"
    case "${status}" in
    403) DOCKER_DAEMON_LAST_CLASS="http-403" ;;
    404) DOCKER_DAEMON_LAST_CLASS="http-404" ;;
    *) DOCKER_DAEMON_LAST_CLASS="http-status" ;;
    esac
    return 1
  fi

  DOCKER_DAEMON_LAST_TIME="${total_time}"
  DOCKER_DAEMON_LAST_REASON=""
  DOCKER_DAEMON_LAST_CLASS=""
}

docker_daemon_manifest_path() {
  local image="$1"
  if [[ "${image}" == */* ]]; then
    echo "${image}"
  else
    echo "library/${image}"
  fi
}

docker_daemon_sum_times() {
  docker_daemon_python "$@" <<'PY'
import sys

print(f"{sum(float(v) for v in sys.argv[1:]):.6f}")
PY
}

docker_daemon_probe_once() {
  local mirror="$1"
  local api_time manifest_time manifest_path
  if ! docker_daemon_request "${mirror}/v2/" "200 401"; then
    DOCKER_DAEMON_LAST_REASON="registry api: ${DOCKER_DAEMON_LAST_REASON}"
    return 1
  fi
  api_time="${DOCKER_DAEMON_LAST_TIME}"

  manifest_path="$(docker_daemon_manifest_path "${MIRROR_TEST_IMAGE}")"
  if ! docker_daemon_request "${mirror}/v2/${manifest_path}/manifests/latest" "200 401"; then
    DOCKER_DAEMON_LAST_REASON="manifest ${MIRROR_TEST_IMAGE}: ${DOCKER_DAEMON_LAST_REASON}"
    return 1
  fi
  manifest_time="${DOCKER_DAEMON_LAST_TIME}"
  DOCKER_DAEMON_LAST_TIME="$(docker_daemon_sum_times "${api_time}" "${manifest_time}")"
}

docker_daemon_median() {
  docker_daemon_python "$@" <<'PY'
import statistics
import sys

values = sorted(float(v) for v in sys.argv[1:])
print(f"{statistics.median(values):.6f}")
PY
}

docker_daemon_test_candidate() {
  local mirror="$1"
  local round median
  local -a times=()

  for ((round = 1; round <= MIRROR_ROUNDS; round++)); do
    if docker_daemon_probe_once "${mirror}"; then
      times+=("${DOCKER_DAEMON_LAST_TIME}")
    else
      echo "[FAIL] ${mirror} reason=${DOCKER_DAEMON_LAST_REASON}"
      return 0
    fi
  done

  median="$(docker_daemon_median "${times[@]}")"
  DOCKER_DAEMON_OK_RESULTS+=("${mirror}|${median}")
  printf '[OK] %s median=%ss\n' "${mirror}" "${median}"
}

docker_daemon_probe_candidates() {
  local mirror
  for mirror in "${DOCKER_DAEMON_CANDIDATES[@]}"; do
    docker_daemon_test_candidate "${mirror}"
  done
}

docker_daemon_probe_direct() {
  local round median
  local -a times=()

  docker_daemon_log "测试 Docker Hub 直连：${MIRROR_DIRECT_REGISTRY}"
  DOCKER_DAEMON_DIRECT_OK="false"
  DOCKER_DAEMON_DIRECT_TIME=""

  for ((round = 1; round <= MIRROR_ROUNDS; round++)); do
    if docker_daemon_probe_once "${MIRROR_DIRECT_REGISTRY}"; then
      times+=("${DOCKER_DAEMON_LAST_TIME}")
    else
      echo "[DIRECT FAIL] ${MIRROR_DIRECT_REGISTRY} reason=${DOCKER_DAEMON_LAST_REASON}"
      return 0
    fi
  done

  median="$(docker_daemon_median "${times[@]}")"
  DOCKER_DAEMON_DIRECT_OK="true"
  DOCKER_DAEMON_DIRECT_TIME="${median}"
  printf '[DIRECT OK] %s median=%ss\n' "${MIRROR_DIRECT_REGISTRY}" "${median}"
}

docker_daemon_mirror_is_faster_than_direct() {
  docker_daemon_python "${DOCKER_DAEMON_DIRECT_TIME}" "${MIRROR_MIN_SPEEDUP_PERCENT}" "$1" <<'PY'
import sys

direct = float(sys.argv[1])
speedup = float(sys.argv[2])
mirror = float(sys.argv[3])
threshold = direct * (100.0 - speedup) / 100.0
if speedup == 0:
    sys.exit(0 if mirror < direct else 1)
sys.exit(0 if mirror <= threshold else 1)
PY
}

docker_daemon_select_results() {
  local -a sorted=()
  local line mirror median index

  if [ "${#DOCKER_DAEMON_OK_RESULTS[@]}" -eq 0 ]; then
    return 0
  fi

  mapfile -t sorted < <(printf '%s\n' "${DOCKER_DAEMON_OK_RESULTS[@]}" | sort -t '|' -k2,2n | tr -d '\r')

  echo "[SELECTED]"
  index=0
  for line in "${sorted[@]}"; do
    mirror="${line%%|*}"
    median="${line##*|}"
    if [ "${DOCKER_DAEMON_DIRECT_OK}" = "true" ] && ! docker_daemon_mirror_is_faster_than_direct "${median}"; then
      printf '[SKIP] %s median=%ss not at least %s%% faster than Docker Hub direct median=%ss\n' \
        "${mirror}" "${median}" "${MIRROR_MIN_SPEEDUP_PERCENT}" "${DOCKER_DAEMON_DIRECT_TIME}"
      continue
    fi
    index=$((index + 1))
    if [ "${index}" -le "${MIRROR_TOP}" ]; then
      DOCKER_DAEMON_SELECTED_MIRRORS+=("${mirror}")
      printf '%d. %s median=%ss\n' "${index}" "${mirror}" "${median}"
    fi
  done
}

docker_daemon_resolve_mirrors() {
  local mode="$1"
  case "${mode}" in
  auto)
    docker_daemon_probe_direct
    docker_daemon_collect_candidates
    docker_daemon_probe_candidates
    docker_daemon_select_results
    if [ "${#DOCKER_DAEMON_SELECTED_MIRRORS[@]}" -gt 0 ]; then
      DOCKER_DAEMON_EFFECTIVE_MIRROR_MODE="auto"
    elif [ "${DOCKER_DAEMON_DIRECT_OK}" = "true" ]; then
      DOCKER_DAEMON_EFFECTIVE_MIRROR_MODE="remove"
      docker_daemon_log "Docker Hub 直连可用，且没有 mirror 达到明显更快阈值；将不配置 registry-mirrors"
    else
      docker_daemon_die "Docker Hub 直连失败，且没有通过实时测试的 Docker Hub mirror，未修改 daemon.json"
    fi
    ;;
  static)
    docker_daemon_static_mirrors
    DOCKER_DAEMON_EFFECTIVE_MIRROR_MODE="static"
    ;;
  remove)
    docker_daemon_log "将移除 registry-mirrors 字段"
    DOCKER_DAEMON_EFFECTIVE_MIRROR_MODE="remove"
    ;;
  esac
}

docker_daemon_confirm_apply() {
  [ "${MIRROR_DRY_RUN}" != "true" ] || return 0
  [ "${MIRROR_AUTO_YES}" != "true" ] || return 0
  if [ ! -t 0 ]; then
    docker_daemon_die "非交互环境修改 daemon.json 必须显式传入 --yes，或在 recipe 中设置 mirror_auto_yes: \"true\""
  fi

  local answer
  read -r -p "将更新 /etc/docker/daemon.json 并按配置重启 Docker，输入 yes 继续: " answer
  [ "${answer}" = "yes" ] || docker_daemon_die "用户取消"
}

docker_daemon_prepare_source_json() {
  local source_file="$1"
  if docker_daemon_as_root test -f "${DOCKER_DAEMON_FILE}"; then
    DOCKER_DAEMON_HAD_FILE="true"
    docker_daemon_as_root cat "${DOCKER_DAEMON_FILE}" >"${source_file}" || docker_daemon_die "读取 ${DOCKER_DAEMON_FILE} 失败"
  else
    DOCKER_DAEMON_HAD_FILE="false"
    printf '{}\n' >"${source_file}"
  fi

  if ! python3 -m json.tool "${source_file}" >/dev/null 2>&1; then
    docker_daemon_die "${DOCKER_DAEMON_FILE} 不是合法 JSON，已停止，未覆盖原文件"
  fi
}

docker_daemon_merge_json() {
  local source_file="$1"
  local output_file="$2"
  local mirror_mode="$3"
  shift 3

  docker_daemon_python "${source_file}" "${output_file}" "${mirror_mode}" "${LOG_MAX_SIZE}" "${LOG_MAX_FILE}" "${LIVE_RESTORE}" "$@" <<'PY'
import json
import sys

source, output, mirror_mode = sys.argv[1], sys.argv[2], sys.argv[3]
log_max_size, log_max_file, live_restore = sys.argv[4], sys.argv[5], sys.argv[6]
mirrors = sys.argv[7:]

try:
    with open(source, "r", encoding="utf-8") as f:
        data = json.load(f)
except json.JSONDecodeError as exc:
    print(f"daemon.json is not valid JSON: {exc}", file=sys.stderr)
    sys.exit(2)

if not isinstance(data, dict):
    print("daemon.json root must be a JSON object", file=sys.stderr)
    sys.exit(2)

data["log-driver"] = "json-file"
log_opts = data.get("log-opts")
if not isinstance(log_opts, dict):
    log_opts = {}
log_opts["max-size"] = log_max_size
log_opts["max-file"] = log_max_file
data["log-opts"] = log_opts
data["live-restore"] = live_restore == "true"

if mirror_mode == "remove":
    data.pop("registry-mirrors", None)
else:
    data["registry-mirrors"] = mirrors

with open(output, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    f.write("\n")
PY
}

docker_daemon_apply_json() {
  local mirror_mode="$1"
  local source_file merged_file target_tmp timestamp
  source_file="$(mktemp)"
  merged_file="$(mktemp)"

  docker_daemon_prepare_source_json "${source_file}"
  docker_daemon_merge_json "${source_file}" "${merged_file}" "${mirror_mode}" "${DOCKER_DAEMON_SELECTED_MIRRORS[@]}"

  docker_daemon_as_root install -d -m 0755 "$(dirname "${DOCKER_DAEMON_FILE}")"
  docker_daemon_as_root install -d -m 0755 "${DOCKER_DAEMON_BACKUP_DIR}"

  if [ "${DOCKER_DAEMON_HAD_FILE}" = "true" ]; then
    timestamp="$(date +%Y%m%d-%H%M%S)"
    DOCKER_DAEMON_BACKUP_FILE="${DOCKER_DAEMON_BACKUP_DIR}/daemon.json.${timestamp}.bak"
    docker_daemon_log "备份已有 daemon.json 到 ${DOCKER_DAEMON_BACKUP_FILE}"
    docker_daemon_as_root cp -a "${DOCKER_DAEMON_FILE}" "${DOCKER_DAEMON_BACKUP_FILE}"
  fi

  target_tmp="$(dirname "${DOCKER_DAEMON_FILE}")/.daemon.json.qs.$$"
  docker_daemon_log "写入 ${DOCKER_DAEMON_FILE}"
  docker_daemon_as_root install -m 0644 "${merged_file}" "${target_tmp}"
  docker_daemon_as_root mv "${target_tmp}" "${DOCKER_DAEMON_FILE}"
  docker_daemon_as_root chmod 0644 "${DOCKER_DAEMON_FILE}"
  rm -f "${source_file}" "${merged_file}"
}

docker_daemon_rollback_and_exit() {
  local reason="$1"
  docker_daemon_warn "${reason}"
  docker_daemon_warn "开始回滚 ${DOCKER_DAEMON_FILE}"

  if [ "${DOCKER_DAEMON_HAD_FILE}" = "true" ] && [ -n "${DOCKER_DAEMON_BACKUP_FILE}" ]; then
    docker_daemon_as_root cp -a "${DOCKER_DAEMON_BACKUP_FILE}" "${DOCKER_DAEMON_FILE}" || true
  else
    docker_daemon_as_root rm -f "${DOCKER_DAEMON_FILE}" || true
  fi

  docker_daemon_as_root systemctl daemon-reload || true
  docker_daemon_as_root systemctl restart docker || true
  docker_daemon_die "${reason}；已尝试回滚 daemon.json"
}

docker_daemon_restart() {
  [ "${RESTART_DOCKER}" = "true" ] || {
    docker_daemon_log "跳过 Docker 重启：RESTART_DOCKER=${RESTART_DOCKER}"
    return 0
  }
  docker_daemon_as_root systemctl daemon-reload
  docker_daemon_as_root systemctl restart docker
}

docker_daemon_prepare_docker_cmd() {
  if docker info >/dev/null 2>&1; then
    DOCKER_DAEMON_DOCKER_USE_SUDO="false"
  else
    DOCKER_DAEMON_DOCKER_USE_SUDO="true"
  fi
}

docker_daemon_docker() {
  if [ "${DOCKER_DAEMON_DOCKER_USE_SUDO}" = "true" ]; then
    docker_daemon_as_root docker "$@"
  else
    docker "$@"
  fi
}

docker_daemon_verify() {
  local mirror_mode="$1"
  local info_file mirror found
  [ "${RESTART_DOCKER}" = "true" ] || return 0

  info_file="$(mktemp)"
  docker_daemon_prepare_docker_cmd
  if ! docker_daemon_docker info >"${info_file}" 2>&1; then
    cat "${info_file}" >&2 || true
    rm -f "${info_file}"
    return 1
  fi

  if [ "${mirror_mode}" != "remove" ]; then
    found="false"
    for mirror in "${DOCKER_DAEMON_SELECTED_MIRRORS[@]}"; do
      if grep -F "${mirror}" "${info_file}" >/dev/null 2>&1; then
        found="true"
        break
      fi
    done
    if [ "${found}" != "true" ]; then
      cat "${info_file}" >&2 || true
      rm -f "${info_file}"
      docker_daemon_warn "docker info 中未看到写入的 Registry Mirrors"
      return 1
    fi
  fi
  rm -f "${info_file}"

  if [ "${MIRROR_VERIFY_IMAGE}" = "none" ]; then
    docker_daemon_log "跳过 docker pull 验证：MIRROR_VERIFY_IMAGE=none"
    return 0
  fi

  docker_daemon_log "验证 docker pull ${MIRROR_VERIFY_IMAGE}"
  docker_daemon_docker pull "${MIRROR_VERIFY_IMAGE}"
}

docker_daemon_apply_and_verify() {
  local mirror_mode="$1"
  docker_daemon_apply_json "${mirror_mode}"
  if ! docker_daemon_restart; then
    docker_daemon_rollback_and_exit "Docker 重启失败"
  fi
  if ! docker_daemon_verify "${mirror_mode}"; then
    docker_daemon_rollback_and_exit "Docker daemon 验证失败"
  fi
  docker_daemon_log "Docker daemon 配置完成"
}

docker_daemon_self_test() {
  docker_daemon_require_cmd python3
  local median total source_file merged_file removed_file candidates_file candidate_count
  source_file="$(mktemp)"
  merged_file="$(mktemp)"
  removed_file="$(mktemp)"
  candidates_file="$(mktemp)"

  median="$(docker_daemon_median 0.300 0.100 0.200)"
  [ "${median}" = "0.200000" ] || docker_daemon_die "self-test median failed: ${median}"

  total="$(docker_daemon_sum_times 0.100 0.250)"
  [ "${total}" = "0.350000" ] || docker_daemon_die "self-test time sum failed: ${total}"

  DOCKER_DAEMON_DIRECT_TIME="1.000"
  MIRROR_MIN_SPEEDUP_PERCENT="20"
  docker_daemon_mirror_is_faster_than_direct "0.800" || docker_daemon_die "self-test speedup threshold failed"
  if docker_daemon_mirror_is_faster_than_direct "0.810"; then
    docker_daemon_die "self-test speedup threshold false positive"
  fi
  MIRROR_MIN_SPEEDUP_PERCENT="0"
  docker_daemon_mirror_is_faster_than_direct "0.999" || docker_daemon_die "self-test zero speedup threshold failed"
  if docker_daemon_mirror_is_faster_than_direct "1.000"; then
    docker_daemon_die "self-test zero speedup threshold false positive"
  fi

  cat >"${candidates_file}" <<'EOF'
# comment
https://a.example/
ftp://invalid.example
https://a.example
https://b.example
EOF
  candidate_count="$(docker_daemon_normalize_candidates_file "${candidates_file}" | wc -l | xargs)"
  [ "${candidate_count}" = "2" ] || docker_daemon_die "self-test candidate normalize failed: ${candidate_count}"

  printf '{"debug":true,"other":{"keep":1},"registry-mirrors":["https://old.example"]}\n' >"${source_file}"
  docker_daemon_merge_json "${source_file}" "${merged_file}" "static" "https://a.example" "https://b.example"
  docker_daemon_python "${merged_file}" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    data = json.load(f)
assert data["debug"] is True
assert data["other"]["keep"] == 1
assert data["log-driver"] == "json-file"
assert data["log-opts"]["max-size"]
assert data["live-restore"] is True
assert data["registry-mirrors"] == ["https://a.example", "https://b.example"]
PY

  docker_daemon_merge_json "${source_file}" "${removed_file}" "remove"
  docker_daemon_python "${removed_file}" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    data = json.load(f)
assert "registry-mirrors" not in data
assert data["debug"] is True
PY

  rm -f "${source_file}" "${merged_file}" "${removed_file}" "${candidates_file}"
  docker_daemon_log "self-test passed"
}

docker_daemon_main() {
  local mirror_mode
  docker_daemon_parse_args "$@"

  if [ "${DOCKER_DAEMON_SHOW_HELP}" = "true" ]; then
    docker_daemon_usage
    return 0
  fi
  if [ "${DOCKER_DAEMON_SELF_TEST}" = "true" ]; then
    docker_daemon_self_test
    return 0
  fi

  docker_daemon_validate_args
  mirror_mode="$(docker_daemon_mirror_mode)"
  docker_daemon_require_dependencies "${mirror_mode}"
  docker_daemon_resolve_mirrors "${mirror_mode}"
  mirror_mode="${DOCKER_DAEMON_EFFECTIVE_MIRROR_MODE}"

  if [ "${MIRROR_DRY_RUN}" = "true" ]; then
    docker_daemon_log "dry-run：未修改 daemon.json，未重启 Docker"
    return 0
  fi

  docker_daemon_confirm_apply
  docker_daemon_apply_and_verify "${mirror_mode}"
}

docker_daemon_main "$@"
