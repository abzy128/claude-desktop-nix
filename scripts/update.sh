#!/usr/bin/env bash
# Updates package.nix to the newest claude-desktop in Anthropic's apt repository.
#
# The repository index publishes a SHA256 for every package, so hashes are read
# straight out of it -- no need to download ~160 MB per architecture to prefetch.
set -euo pipefail

readonly REPO_BASE="https://downloads.claude.ai/claude-desktop/apt/stable"
readonly ARCHES=(amd64 arm64)

log() { echo "[INFO] $*"; }
err() { echo "[ERROR] $*" >&2; }

ensure_root() {
  if [ ! -f flake.nix ] || [ ! -f package.nix ]; then
    err "Run from repository root"
    exit 1
  fi
}

ensure_tools() {
  for tool in curl nix; do
    command -v "$tool" >/dev/null || { err "$tool is required"; exit 1; }
  done
}

# Cache each architecture's index so it is fetched once per run.
fetch_index() {
  local arch="$1"
  local cache="${TMPDIR:-/tmp}/claude-desktop-Packages-${arch}.$$"
  if [ ! -s "$cache" ]; then
    curl -fsSL "${REPO_BASE}/dists/stable/main/binary-${arch}/Packages" >"$cache"
  fi
  cat "$cache"
}

current_version() {
  sed -n 's/^  version = "\([^"]*\)";.*/\1/p' package.nix | head -1
}

# The index lists every published version; the newest is the last by version sort.
latest_version() {
  fetch_index amd64 \
    | sed -n 's/^Version: //p' \
    | sort -V \
    | tail -1
}

# Stanzas are separated by blank lines, so the SHA256 following a Version line
# belongs to that same package.
index_hash() {
  local arch="$1" version="$2" hex
  hex=$(fetch_index "$arch" | awk -v want="Version: ${version}" '
    $0 == want { found = 1; next }
    found && /^SHA256: / { print $2; exit }
  ')
  if [ -z "$hex" ]; then
    err "No SHA256 for ${version} on ${arch}"
    return 1
  fi
  nix hash convert --hash-algo sha256 --to sri "$hex"
}

set_version() {
  sed -i "s|^  version = \".*\";|  version = \"$1\";|" package.nix
}

# Rewrites the hash inside the platformMap entry whose debArch matches.
set_hash() {
  local arch="$1" hash="$2" tmp
  tmp=$(mktemp)
  awk -v arch="$arch" -v hash="$hash" '
    $0 ~ "debArch = \"" arch "\"" { in_entry = 1 }
    in_entry && /hash = / { sub(/hash = "[^"]*"/, "hash = \"" hash "\""); in_entry = 0 }
    { print }
  ' package.nix >"$tmp"
  mv "$tmp" package.nix
}

update_to() {
  local version="$1"
  log "Updating to ${version}"

  # Resolve every hash before touching package.nix, so a missing architecture
  # cannot leave the file half-updated.
  local -a hashes=()
  local arch hash
  for arch in "${ARCHES[@]}"; do
    hash=$(index_hash "$arch" "$version") || exit 1
    log "${arch}: ${hash}"
    hashes+=("$hash")
  done

  set_version "$version"
  local i
  for i in "${!ARCHES[@]}"; do
    set_hash "${ARCHES[$i]}" "${hashes[$i]}"
  done

  log "Updating flake.lock"
  nix flake update

  log "Verifying build"
  nix build .#claude-desktop
}

usage() {
  cat <<EOF
Usage: $0 [--check] [--version VERSION]

  --check            Exit 1 if an update is available, without changing anything.
  --version VERSION  Update to a specific version instead of the newest.
EOF
}

main() {
  ensure_root
  ensure_tools

  local check=false target=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --check) check=true; shift ;;
      --version) target="${2:-}"; shift 2 ;;
      --help) usage; exit 0 ;;
      *) err "Unknown argument: $1"; usage; exit 1 ;;
    esac
  done

  local current latest
  current=$(current_version)
  latest=${target:-$(latest_version)}

  log "Current version: ${current}"
  log "Latest version: ${latest}"

  if [ "$current" = "$latest" ]; then
    log "Already up to date"
    exit 0
  fi

  if [ "$check" = true ]; then
    log "Update available: ${current} -> ${latest}"
    exit 1
  fi

  update_to "$latest"
  git diff --stat package.nix flake.lock || true
}

trap 'rm -f "${TMPDIR:-/tmp}"/claude-desktop-Packages-*.$$' EXIT

main "$@"
