#!/bin/bash
# @qs template

# @description Install or upgrade the QS CLI from a published GitHub release into a user-writable bin directory.
# @step Detect the current OS and CPU architecture.
# @step Download the selected QS release asset from GitHub.
# @step Install the executable as qs and print the detected version.
# @platform linux/ubuntu>=22.04 linux/debian>=12 linux/alpine>=3.19 darwin
# @shell bash
# @requires bash curl chmod mkdir mktemp mv tr uname
# @effects network-download file-write
# @network github.com

# @arg QS release tag, or latest for the latest GitHub release.
QS_VERSION="latest"

# @arg GitHub owner/repo containing QS release assets.
QS_REPO="yuanboshe/quick-setup"

# @arg Directory where the qs executable should be installed.
QS_INSTALL_DIR="${HOME}/.local/bin"

# @arg Installed executable name.
QS_BINARY_NAME="qs"

detect_platform() {
  local os arch
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  arch="$(uname -m | tr '[:upper:]' '[:lower:]')"

  case "${os}" in
    linux*) os="linux" ;;
    darwin*) os="darwin" ;;
    mingw*|msys*|cygwin*) os="windows" ;;
    *) echo "unsupported os: ${os}" >&2; return 1 ;;
  esac

  case "${arch}" in
    x86_64|amd64) arch="amd64" ;;
    arm64|aarch64) arch="arm64" ;;
    *) echo "unsupported arch: ${arch}" >&2; return 1 ;;
  esac

  if [ "${os}" = "windows" ]; then
    printf 'qs-%s-%s.exe\n' "${os}" "${arch}"
  else
    printf 'qs-%s-%s\n' "${os}" "${arch}"
  fi
}

download_url() {
  local asset="$1"
  if [ "${QS_VERSION}" = "latest" ]; then
    printf 'https://github.com/%s/releases/latest/download/%s\n' "${QS_REPO}" "${asset}"
  else
    printf 'https://github.com/%s/releases/download/%s/%s\n' "${QS_REPO}" "${QS_VERSION}" "${asset}"
  fi
}

main() {
  local asset url tmp target
  asset="$(detect_platform)"
  url="$(download_url "${asset}")"
  tmp="$(mktemp)"
  target="${QS_INSTALL_DIR}/${QS_BINARY_NAME}"

  echo "Downloading ${url}"
  curl -fsSL "${url}" -o "${tmp}"
  chmod +x "${tmp}"

  mkdir -p "${QS_INSTALL_DIR}"
  mv "${tmp}" "${target}"

  echo "Installed ${target}"
  "${target}" version || true
}

main "$@"
