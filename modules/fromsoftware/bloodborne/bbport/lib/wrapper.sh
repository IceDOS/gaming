#!@shell@
# The AppImage's AppRun mounts its /nix over the host's, which hides host icon themes, fonts
# and the paths portals get. Overlay its store onto the host store instead.
exec 3< <(exec @appimage@ --appimage-mount)
mounter=$!
# Overlay layers may not lie inside each other, so the patched files go outside /nix/store.
patched=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/bbport-overlay.XXXXXX") || exit 1
trap 'kill "$mounter" 2>/dev/null; rm -rf "$patched"' EXIT
cp -r --no-preserve=mode @overlay@/. "$patched"
read -r mnt <&3 || exit 1

# BBSC looks for saves under <cwd>/user, but the launcher runs from the read-only AppImage, so it
# never backs them up and never gives its bell kit while still disabling the vanilla bells.
export BBSC_SAVE_DIR="${BBSC_SAVE_DIR:-${BB_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/bbport}/user/savedata/1/CUSA00207/SPRJ0005}"

# The last source is the top layer: it replaces libbbnet.so with the BBSC memory fix.
@bwrap@ --dev-bind / / --die-with-parent \
  --overlay-src /nix/store --overlay-src "$mnt/nix/store" --overlay-src "$patched" --ro-overlay /nix/store \
  -- "$mnt/entrypoint" "$@" &
app=$!
# Backgrounded, so a signal reaches the trap at once instead of after the launcher exits.
trap 'kill "$app" 2>/dev/null' INT TERM HUP
wait "$app"
status=$?
while kill -0 "$app" 2>/dev/null; do
  wait "$app"
  status=$?
done
exit "$status"
