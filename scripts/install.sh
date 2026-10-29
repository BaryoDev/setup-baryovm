#!/usr/bin/env bash
# Installs BaryoVM. All inputs arrive as environment variables, never interpolated.
# Usage: install.sh resolve | install
set -euo pipefail

REPO="BaryoDev/BaryoVM"
BASE="https://github.com/${REPO}/releases/download"

die() { echo "setup-baryovm: error: $*" >&2; exit 1; }

# Tests only: a local file:// directory holding the archive and checksums.txt.
# Needs both variables, so a stray BARYOVM_DOWNLOAD_BASE cannot move the trust root.
if [ -n "${BARYOVM_DOWNLOAD_BASE:-}" ]; then
  [ "${BARYOVM_TEST_DOWNLOAD:-}" = "1" ] || die "BARYOVM_DOWNLOAD_BASE is for this action's own tests and needs BARYOVM_TEST_DOWNLOAD=1"
  [[ "$BARYOVM_DOWNLOAD_BASE" == file://* ]] || die "BARYOVM_DOWNLOAD_BASE must be a file:// path"
  BASE="$BARYOVM_DOWNLOAD_BASE"
fi

fetch() {
  local proto=()
  [[ "$2" == https://* ]] && proto=(--proto '=https' --proto-redir '=https')
  curl -fsSL ${proto[@]+"${proto[@]}"} ${auth[@]+"${auth[@]}"} -o "$1" "$2"
}

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
archive_dir() { echo "${RUNNER_TOOL_CACHE:?}/baryovm-archives/$1/$(os_name)-$(arch_name)"; }

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
    v="$(curl -fsSL --proto '=https' --proto-redir '=https' ${auth[@]+"${auth[@]}"} -H "Accept: application/vnd.github+json" \
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
    echo "archive-dir=$(archive_dir "$v")"
  } >> "${GITHUB_OUTPUT:?}"
}

# The cache holds the archive, never the binary. Every run fetches checksums.txt,
# verifies the archive (cached or fresh) and extracts a new binary from it.
install() {
  local v="${INPUT_VERSION:?}"
  local dir cache archive work
  dir="$(tool_dir "$v")"
  cache="$(archive_dir "$v")"
  archive="baryovm_${v}_$(os_name)_$(arch_name).tar.gz"
  work="$(mktemp -d "${RUNNER_TEMP:?}/baryovm-dl.XXXXXX")"
  auth=()
  [ -n "${INPUT_TOKEN:-}" ] && [[ "$BASE" == https://github.com/* ]] && auth=(-H "Authorization: Bearer ${INPUT_TOKEN}")
  fetch "$work/checksums.txt" "$BASE/v$v/checksums.txt" || die "download failed: $BASE/v$v/checksums.txt"
  mkdir -p "$cache"
  if [ -f "$cache/$archive" ]; then
    echo "using cached $archive"
  else
    echo "downloading $archive for v$v"
    fetch "$cache/$archive" "$BASE/v$v/$archive" || die "download failed: $BASE/v$v/$archive"
  fi
  local want got
  want="$(awk -v f="$archive" '$2 == f { print $1 }' "$work/checksums.txt")"
  [ -n "$want" ] || die "checksums.txt has no line for $archive"
  got="$(sha256_of "$cache/$archive")"
  if [ "$got" != "$want" ]; then
    rm -f "$cache/$archive"
    die "checksum mismatch for $archive: expected $want, got $got"
  fi
  echo "checksum ok: $got"
  rm -rf "$dir.tmp"
  mkdir -p "$dir.tmp"
  tar -xzf "$cache/$archive" -C "$dir.tmp" baryovm
  rm -rf "$dir"
  mv "$dir.tmp" "$dir"
  rm -rf "$work"
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
