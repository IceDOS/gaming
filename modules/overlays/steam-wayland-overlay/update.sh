#!/usr/bin/env nix-shell
#! nix-shell -i bash -p curl git jq nix

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
CORE="${ICEDOS_CORE:-$REPO_ROOT/.icedos-core}"
[ -d "$CORE" ] || CORE="$REPO_ROOT/../core"
[ -f "$CORE/lib/update-lib.sh" ] || {
  echo "ERROR: core not found; set ICEDOS_CORE=/path/to/IceDOS/core" >&2
  exit 1
}
# shellcheck source=/dev/null
. "$CORE/lib/update-lib.sh"

PIN="$SCRIPT_DIR/source.json"
REPO="GloriousEggroll/proton-ge-custom"
BRANCH="master"

# Overlay paths, read from the pin so package.nix and this script cannot drift;
# the updater bumps only when these change.
mapfile -t OVERLAY_PATHS < <(jq -r '(.overlayPaths // [])[]' "$PIN")
[ "${#OVERLAY_PATHS[@]}" -gt 0 ] || error "source.json has no overlayPaths"

# prefetch_sparse_fetchgithub OWNER REPO REV — SRI of the *filtered* tree. Sparse
# checkout changes the hash; ask Nix with a wrong hash and read the one it reports.
prefetch_sparse_fetchgithub() {
  local owner="$1" repo="$2" rev="$3" expr got path
  expr="$(mktemp)"
  {
    printf 'with import <nixpkgs> {};\n'
    printf 'fetchFromGitHub {\n'
    printf '  owner = "%s";\n' "$owner"
    printf '  repo = "%s";\n' "$repo"
    printf '  rev = "%s";\n' "$rev"
    printf '  hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";\n'
    printf '  sparseCheckout = [\n'
    for path in "${OVERLAY_PATHS[@]}"; do
      printf '    "%s"\n' "$path"
    done
    printf '  ];\n'
    printf '}\n'
  } >"$expr"
  got="$(
    nix-build --no-out-link "$expr" 2>&1 \
      | sed -n 's/.*got:[[:space:]]*\(sha256-.*\)\r\?$/\1/p' \
      | tail -1
  )"
  rm -f "$expr"
  [ -n "$got" ] || return 1
  echo "$got"
}

# vkroots_rev_from REPO_DIR REV — vkroots commit for GE's overlay, lockstepped with
# that rev's dxvk-nvapi submodule; REPO_DIR is the partial proton-ge clone from main().
vkroots_rev_from() {
  local repo_dir="$1" proton_rev="$2" nvapi nvapi_url nvapi_remote
  nvapi=$(git -C "$repo_dir" ls-tree "$proton_rev" dxvk-nvapi | awk '{print $3}')
  [ -n "$nvapi" ] || return 1

  nvapi_url=$(git -C "$repo_dir" show "$proton_rev:.gitmodules" \
    | awk -F'=' '/submodule "dxvk-nvapi"/{f=1} f && /^[[:space:]]*url/{gsub(/[[:space:]]/,"",$2); print $2; exit}')
  [ -n "$nvapi_url" ] || return 1

  nvapi_remote="$(dirname "$repo_dir")/dxvk-nvapi"
  git clone --quiet --filter=blob:none --no-checkout "$nvapi_url" "$nvapi_remote" 2>/dev/null
  git -C "$nvapi_remote" fetch --quiet origin "$nvapi" 2>/dev/null
  git -C "$nvapi_remote" ls-tree "$nvapi" external/vkroots | awk '{print $3}'
}

main() {
  banner "steam-wayland-overlay updater"

  info "Finding latest $REPO $BRANCH HEAD..."
  local latest
  latest=$(git_head "https://github.com/$REPO.git" "$BRANCH")
  require_nonempty rev "$latest"
  info "  Latest: $latest"

  local current
  current=$(read_pin "$PIN" .rev)
  if [ "$latest" = "$current" ]; then
    info "  Already up to date ($latest)"
    return
  fi
  info "  Current: ${current:-none}"

  local date
  # Global so the EXIT trap can still refer to it.
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  # Partial clone: blobs only for the paths we diff, so master churn elsewhere is free.
  info "  Cloning $REPO (partial)..."
  git clone --quiet --filter=blob:none --no-checkout --single-branch \
    --branch "$BRANCH" "https://github.com/$REPO.git" "$tmp/repo" 2>/dev/null

  if [ -n "$current" ]; then
    git -C "$tmp/repo" fetch --quiet origin "$current" 2>/dev/null || true
    # Fail closed: an unreachable pin (force-push) must not read as "changed".
    if ! git -C "$tmp/repo" cat-file -e "$current^{commit}" 2>/dev/null; then
      warn "pinned rev $current not reachable from origin; skipping (no unsafe bump)"
      return
    fi
    if git -C "$tmp/repo" diff --quiet "$current" "$latest" -- "${OVERLAY_PATHS[@]}" 2>/dev/null; then
      warn "no changes to overlay-solution paths between $current and $latest; skipping"
      return
    fi
  fi

  date="$(git -C "$tmp/repo" show -s --format='%cs' "$latest" 2>/dev/null || true)"
  [ -n "$date" ] || date="$(date +%F)"
  local version="unstable-$date"

  info "  Computing sparse-checkout hash..."
  local hash
  hash=$(prefetch_sparse_fetchgithub "${REPO%%/*}" "${REPO##*/}" "$latest" || echo "")
  require_nonempty steam-wayland-overlay "$version" "$latest" "$hash"
  info "  Hash: $hash"

  info "  Resolving vkroots from $latest's dxvk-nvapi submodule..."
  local vkrootsRev vkrootsHash overlayPathsJson
  vkrootsRev=$(vkroots_rev_from "$tmp/repo" "$latest" || echo "")
  require_nonempty vkroots_rev "$vkrootsRev"
  vkrootsHash=$(prefetch_github "misyltoad" "vkroots" "$vkrootsRev" || echo "")
  require_nonempty steam-wayland-overlay/vkroots "$vkrootsRev" "$vkrootsHash"
  info "  vkroots: $vkrootsRev"

  overlayPathsJson="$(jq -nc '$ARGS.positional' --args "${OVERLAY_PATHS[@]}")"
  jq -n --arg version "$version" --arg rev "$latest" --arg hash "$hash" \
    --arg vkRev "$vkrootsRev" --arg vkHash "$vkrootsHash" \
    --argjson overlayPaths "$overlayPathsJson" \
    '{version: $version, rev: $rev, hash: $hash,
      vkrootsRev: $vkRev, vkrootsHash: $vkHash, overlayPaths: $overlayPaths}' \
    | write_pin "$PIN"
  info "  Updated: $version ($vkrootsRev)"
}

main "$@"

echo ""
info "Done. Review changes with: git diff $SCRIPT_DIR"
