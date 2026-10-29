#!/usr/bin/env bash
# Installs BaryoVM. All inputs arrive as environment variables, never interpolated.
# Usage: install.sh resolve | install
set -euo pipefail

REPO="BaryoDev/BaryoVM"
# Tests only: point at a local directory (file://...) holding the archive and checksums.txt.
BASE="${BARYOVM_DOWNLOAD_BASE:-https://github.com/${REPO}/releases/download}"

die() { echo "setup-baryovm: error: $*" >&2; exit 1; }

arch_name() {
  case "${RUNNER_ARCH:-}" in
    X64) echo amd64 ;;
    ARM64) echo arm64 ;;
    *) die "unsupported runner architecture: ${RUNNER_ARCH:-unset}" ;;
  esac
}

os_name() {
  case "${RUNNER_OS:-}" in
    Linux) echo linux ;;
    macOS) echo darwin ;;
    *) die "unsupported runner OS: ${RUNNER_OS:-unset}" ;;
  esac
}

tool_dir() { echo "${RUNNER_TOOL_CACHE:?}/baryovm/$1/$(os_name)-$(arch_name)"; }

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
  else die "neither sha256sum nor shasum is available"; fi
}

resolve() {
  local v="${INPUT_VERSION:-}"
  [ -n "$v" ] || die "version is required"
  if [ "$v" = "latest" ]; then
    [ "${INPUT_ALLOW_LATEST:-false}" = "true" ] || die "version 'latest' is refused. Pin a version, or set allow-latest: true."
    local auth=()
    [ -n "${INPUT_TOKEN:-}" ] && auth=(-H "Authorization: Bearer ${INPUT_TOKEN}")
    v="$(curl -fsSL ${auth[@]+"${auth[@]}"} -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/${REPO}/releases/latest" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n1)"
    [ -n "$v" ] || die "could not resolve the latest release"
  fi
  v="${v#v}"
  [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$ ]] || die "invalid version: $v"
  local dir
  dir="$(tool_dir "$v")"
  {
    echo "version=$v"
    echo "dir=$dir"
  } >> "${GITHUB_OUTPUT:?}"
}

install() {
  local v="${INPUT_VERSION:?}"
  local dir
  dir="$(tool_dir "$v")"
  if [ -x "$dir/baryovm" ]; then
    echo "baryovm $v already present in $dir"
  else
    local archive
    archive="baryovm_${v}_$(os_name)_$(arch_name).tar.gz"
    local work
    work="$(mktemp -d "${RUNNER_TEMP:?}/baryovm-dl.XXXXXX")"
    local auth=()
    [ -n "${INPUT_TOKEN:-}" ] && [[ "$BASE" == https://github.com/* ]] && auth=(-H "Authorization: Bearer ${INPUT_TOKEN}")
    echo "downloading $archive and checksums.txt for v$v"
    curl -fsSL ${auth[@]+"${auth[@]}"} -o "$work/$archive" "$BASE/v$v/$archive" || die "download failed: $BASE/v$v/$archive"
    curl -fsSL ${auth[@]+"${auth[@]}"} -o "$work/checksums.txt" "$BASE/v$v/checksums.txt" || die "download failed: $BASE/v$v/checksums.txt"
    local want
    want="$(awk -v f="$archive" '$2 == f { print $1 }' "$work/checksums.txt")"
    [ -n "$want" ] || die "checksums.txt has no line for $archive"
    local got
    got="$(sha256_of "$work/$archive")"
    if [ "$got" != "$want" ]; then
      die "checksum mismatch for $archive: expected $want, got $got"
    fi
    echo "checksum ok: $got"
    mkdir -p "$dir.tmp"
    tar -xzf "$work/$archive" -C "$dir.tmp" baryovm
    rm -rf "$dir"
    mv "$dir.tmp" "$dir"
    rm -rf "$work"
  fi
  chmod +x "$dir/baryovm"
  local home="${RUNNER_TEMP}/baryovm-home"
  mkdir -p "$home"
  echo "$dir" >> "${GITHUB_PATH:?}"
  echo "BARYOVM_HOME=$home" >> "${GITHUB_ENV:?}"
  echo "installed baryovm $v to $dir"
}

case "${1:-}" in
  resolve) resolve ;;
  install) install ;;
  *) die "usage: install.sh resolve|install" ;;
esac
