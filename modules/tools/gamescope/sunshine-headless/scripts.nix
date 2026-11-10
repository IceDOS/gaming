{
  pkgs,
  lib,
  # icedos.gaming.gamescope.sunshine-headless
  cfg,
  apps,
  gamescopePkg,
  xnudge,
  xdg-desktop-portal-gamescope,
  sunshinePortalConfig,
}:

let
  inherit (cfg)
    fsrSharpness
    hdr
    inputInjection
    mangoApp
    nativeWayland
    realtime
    renderHeight
    renderWidth
    sdrContentNits
    sdrGamutWideness
    upscaleFilter
    ;

  gamescopeRegrowTimeout = cfg.regrowTimeout;
  gamescopeUnit = "sunshine-headless-gamescope.service";
  stoppingMarker = "sunshine-headless-gamescope-stopping";

  # Shadow `mangoapp` with an X11-forcing wrapper (native-Wayland GLFW coredumps, MangoHud #1741).
  mangoappWrapper = pkgs.writeShellScriptBin "mangoapp" ''
    unset WAYLAND_DISPLAY
    # gamescope exports DISPLAY (its first Xwayland) to the overlays it spawns.
    export XDG_SESSION_TYPE=x11 GDK_BACKEND=x11
    exec ${pkgs.mangohud}/bin/mangoapp "$@"
  '';

  # Per-app gamescope settings as one associative array: `app_g[hdr]`, `app_g[render_w]`, ...
  # `app_setup` re-assigns the whole array per app, so no stale key survives.
  appGamescopeLine =
    app:
    let
      inherit (app.gamescope)
        fsrSharpness
        hdr
        inputInjection
        mangoApp
        nativeWayland
        realtime
        renderHeight
        renderWidth
        sdrContentNits
        sdrGamutWideness
        upscaleFilter
        ;
    in
    "      app_g=(${
            lib.concatStringsSep " " [
              "[hdr]=${if hdr then "1" else "0"}"
              "[nits]=${toString sdrContentNits}"
              "[gamut]=${toString sdrGamutWideness}"
              "[render_w]=${toString renderWidth}"
              "[render_h]=${toString renderHeight}"
              "[upscale]=${lib.escapeShellArg upscaleFilter}"
              "[fsr]=${toString fsrSharpness}"
              "[native_wayland]=${if nativeWayland then "1" else "0"}"
              "[input_inject]=${if inputInjection then "1" else "0"}"
              "[mango]=${if mangoApp then "1" else "0"}"
              "[realtime]=${if realtime then "1" else "0"}"
            ]
          })";

  appCases = lib.concatMapStrings (app: ''
    ${lib.escapeShellArg app.slug})
      app_steam_mode=${if app.steamMode then "1" else "0"}
      ${appGamescopeLine app}
      ;;
  '') apps;
in
{
  waylandDisplay = "gamescope-0";
  inputBridge = inputInjection;

  packages = [
    gamescopePkg
    xnudge
    pkgs.xprop
    pkgs.xwininfo
  ]
  ++ lib.optional mangoApp mangoappWrapper;

  portal = {
    serviceDirs = [ "${xdg-desktop-portal-gamescope}/share/dbus-1/services" ];
    environment = {
      XDG_DATA_DIRS = "${pkgs.xdg-desktop-portal}/share:${xdg-desktop-portal-gamescope}/share";
      NIX_XDG_DESKTOP_PORTAL_DIR = "${xdg-desktop-portal-gamescope}/share/xdg-desktop-portal/portals";
      XDG_DESKTOP_PORTAL_DIR = "${xdg-desktop-portal-gamescope}/share/xdg-desktop-portal/portals";
      XDG_CONFIG_HOME = "${sunshinePortalConfig}";
      XDG_CURRENT_DESKTOP = "gamescope";
      WAYLAND_DISPLAY = "gamescope-0";
      G_MESSAGES_DEBUG = "all";
    };
  };

  helpers = ''
    declare -A app_g=()
    app_steam_mode=0

    # gamescope's Xwayland displays: 0 hosts Steam and the control atoms, 1 the games.
    # Their numbers are whatever was free (KWin can hold :0 and :1), so see resolve_gamescope_displays.
    gs_x0=""
    gs_x1=""
    # Match each X root's GAMESCOPE_PID against the gamescope unit's cgroup.
    resolve_gamescope_displays() {
      local cg s d pid id
      gs_x0=""
      gs_x1=""
      cg="$(systemctl --user show -p ControlGroup --value ${gamescopeUnit} 2>/dev/null || true)"
      [ -n "$cg" ] && [ -r "/sys/fs/cgroup$cg/cgroup.procs" ] || return 1
      for s in /tmp/.X11-unix/X*; do
        [ -S "$s" ] || continue
        d=":''${s##*/X}"
        pid="$(DISPLAY="$d" timeout 2 xprop -root GAMESCOPE_PID 2>/dev/null | sed -n 's/^.*= //p' || true)"
        case "$pid" in "" | *[!0-9]*) continue ;; esac
        grep -qx "$pid" "/sys/fs/cgroup$cg/cgroup.procs" 2>/dev/null || continue
        id="$(DISPLAY="$d" timeout 2 xprop -root GAMESCOPE_XWAYLAND_SERVER_ID 2>/dev/null | sed -n 's/^.*= //p' || true)"
        case "$id" in
          0) gs_x0="$d" ;;
          1) gs_x1="$d" ;;
        esac
      done
      [ -n "$gs_x0" ] && [ -n "$gs_x1" ]
    }

    # gamescope sets the atoms shortly after its socket appears.
    wait_gamescope_displays() {
      for _ in $(seq 1 100); do
        resolve_gamescope_displays && return 0
        sleep 0.1
      done
      echo "sunshine-headless: gamescope's Xwayland displays not found (no X root carries its GAMESCOPE_PID)" >&2
      return 1
    }

    # gamescope (--steam) presents a window only when the app that owns it is the
    # focused app, and an Xwayland window carries its app id in STEAM_GAME, which nothing
    # sets for an app the module launches itself. Tag the app's windows, aim the baselayer
    # at the same id, and re-roll the focus until gamescope lists it. Ids come from the
    # app's SteamAppId, else the window pid (nonzero and unique, which is all gamescope needs).
    # Only reachable through app_call's dynamic dispatch.
    # shellcheck disable=SC2329
    app_present() {
      local w wpid a
      while read -r w; do
        [ -n "$w" ] || continue
        wpid="$(DISPLAY="$gs_x0" xprop -id "$w" _NET_WM_PID 2>/dev/null | grep -oE '[0-9]+$' || true)"
        [ -n "$wpid" ] || continue
        a="''${app_appid:-}"
        if [ -z "$a" ]; then
          a="$(tr '\0' '\n' <"/proc/$wpid/environ" 2>/dev/null | sed -n 's/^SteamAppId=//p' | head -n1 || true)"
        fi
        case "$a" in "" | 0 | *[!0-9]*) a="$wpid" ;; esac
        if ! DISPLAY="$gs_x0" xprop -id "$w" STEAM_GAME 2>/dev/null | grep -q "= $a$"; then
          DISPLAY="$gs_x0" xprop -id "$w" -f STEAM_GAME 32c -set STEAM_GAME "$a" 2>/dev/null || true
        fi
        app_appid="$a"
      done < <(DISPLAY="$gs_x0" xwininfo -root -children 2>/dev/null | grep -oE '0x[0-9a-f]+')
      [ -n "''${app_appid:-}" ] || return 0
      if [ "''${last_baselayer:-}" != "$app_appid" ]; then
        DISPLAY="$gs_x0" xprop -root -f GAMESCOPECTRL_BASELAYER_APPID 32c \
          -set GAMESCOPECTRL_BASELAYER_APPID "$app_appid" 2>/dev/null || true
        last_baselayer="$app_appid"
      fi
      if game_in_focusable "$app_appid"; then
        focus_tick=0
      else
        focus_tick=$(( ''${focus_tick:-0} + 1 ))
        if [ $(( focus_tick % 5 )) -eq 1 ]; then
          reroll_gamescope_focus
        fi
      fi
    }

    # Only reachable through app_call's dynamic dispatch.
    # shellcheck disable=SC2329
    game_in_focusable() {
      local apps
      apps="$(DISPLAY="$gs_x0" xprop -root GAMESCOPE_FOCUSABLE_APPS 2>/dev/null | sed -n 's/^.*= //p' | tr -d ' ' || true)"
      case ",$apps," in *",$1,"*) return 0 ;; esac
      return 1
    }

    # Dirtying the focus re-rolls it; every 5th tick, since a window gamescope rightly
    # rejects never reaches its list.
    # Only reachable through app_call's dynamic dispatch.
    # shellcheck disable=SC2329
    reroll_gamescope_focus() {
      DISPLAY="$gs_x1" sunshine-headless-xnudge 2>/dev/null || true
    }

    gamescope_wrapper=(/run/wrappers/bin/sunshine-headless-gamescope)

    # The running instance must match the incoming app's effective settings, so they all
    # join the marker; `start` compares it and restarts gamescope on a mismatch.
    gamescope_marker_now() {
      printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s' \
        "${gamescopePkg}" \
        "''${app_g[input_inject]:-${if inputInjection then "1" else "0"}}" \
        "''${app_g[realtime]:-${if realtime then "1" else "0"}}" \
        "''${app_steam_mode:-0}" \
        "''${app_g[hdr]:-${if hdr then "1" else "0"}}" \
        "''${app_g[nits]:-${toString sdrContentNits}}" \
        "''${app_g[gamut]:-${toString sdrGamutWideness}}" \
        "''${app_g[render_w]:-${toString renderWidth}}" \
        "''${app_g[render_h]:-${toString renderHeight}}" \
        "''${app_g[upscale]:-${upscaleFilter}}"
      # --mangoapp is steam mode only, so a plain app must not restart gamescope over it.
      if [ "''${app_steam_mode:-0}" = 1 ]; then
        printf '|%s' "''${app_g[mango]:-${if mangoApp then "1" else "0"}}"
      fi
      printf '\n'
    }

    # Intentional stop: the marker tells the ExecStopPost drain to leave the apps alone.
    # No is-active guard: a crash-looping unit exits 3 there, skipping the stop that cancels its restart.
    stop_gamescope_unit() {
      : >"$rt/${stoppingMarker}"
      systemctl --user stop --quiet ${gamescopeUnit} 2>/dev/null || true
      # stop blocks through ExecStopPost; clear a marker no drain consumed.
      rm -f "$rt/${stoppingMarker}"
    }

    stop_gamescope() {
      # Killing a Restart=always unit (or freezing it) instead of stopping it latches it on systemd 261.
      stop_gamescope_unit
      systemctl --user reset-failed ${gamescopeUnit} 2>/dev/null || true
      for _ in $(seq 1 30); do
        [ ! -S "$rt/gamescope-0" ] && break
        sleep 0.1
      done
      rm -f "$rt/gamescope-0" "$rt/sunshine-headless-gamescope-params" "$rt/sunshine-headless-gamescope-bin"
    }

    # gamescope never reconnects after a PipeWire restart, so its capture node stays dead.
    # Only the probe qualifies: a session gamescope may still host a running app.
    probe_gamescope_stale() {
      local pw gs
      [ "$(cat "$rt/sunshine-headless-gamescope-params" 2>/dev/null || true)" = "1 1 1 0" ] || return 1
      pw="$(systemctl --user show -p ActiveEnterTimestampMonotonic --value pipewire.service 2>/dev/null || true)"
      gs="$(systemctl --user show -p ActiveEnterTimestampMonotonic --value ${gamescopeUnit} 2>/dev/null || true)"
      [ "''${gs:-0}" -gt 0 ] && [ "''${pw:-0}" -gt "''${gs:-0}" ]
    }

    start_gamescope() {
      local w="$1" h="$2" fps="$3" hdr_on="$4"
      local rw="''${app_g[render_w]:-${toString renderWidth}}" rh="''${app_g[render_h]:-${toString renderHeight}}"
      [ "$rw" = "0" ] && rw="$w"
      [ "$rh" = "0" ] && rh="$h"
      local hdr_args=()
      if [ "''${app_g[hdr]:-${if hdr then "1" else "0"}}" = 1 ] && [ "$hdr_on" = 1 ]; then
        hdr_args=(
          --hdr-enabled
          --hdr-debug-force-output
          --hdr-debug-force-support
          --sdr-gamut-wideness "''${app_g[gamut]:-${toString sdrGamutWideness}}"
          --hdr-sdr-content-nits "''${app_g[nits]:-${toString sdrContentNits}}"
        )
      fi
      upscale_args=()
      if [ -n "''${app_g[upscale]:-${upscaleFilter}}" ]; then
        upscale_args=(-F "''${app_g[upscale]:-${upscaleFilter}}" --fsr-sharpness "''${app_g[fsr]:-${toString fsrSharpness}}")
      fi
      rt_args=()
      [ "''${app_g[realtime]:-${if realtime then "1" else "0"}}" = 1 ] && rt_args=(--rt)
      # The gid shim is what turns the libvirtualhid devices into this session's input devices.
      gscope_wrap=()
      input_args=()
      if [ "''${app_g[input_inject]:-${if inputInjection then "1" else "0"}}" = 1 ]; then
        gscope_wrap=(/run/wrappers/bin/sunshine-headless-gid)
        # Exact name match, so host devices are never grabbed; the primary daemon's
        # libvirtualhid devices share these names and would be grabbed if it streams concurrently.
        input_args=(
          --setenv=HEADLESS_INPUT_KEYBOARD="libvirtualhid Keyboard"
          --setenv=HEADLESS_INPUT_MOUSE="libvirtualhid Mouse"
          --setenv=HEADLESS_INPUT_MOUSE_ABS="libvirtualhid Mouse (Absolute)"
          --setenv=HEADLESS_INPUT_ACTIVE_LINK="$rt/sunshine-portal/bus"
          --setenv=HEADLESS_INPUT_ACTIVE_TARGET="$rt/sunshine-portal/gamescope/bus"
        )
      fi
      # Plain apps do not need (and are not gated by) --steam; the mangoapp overlay is
      # a full-screen X window and would fight them for focus, so it stays steam-only.
      steam_args=()
      mango_args=()
      if [ "''${app_steam_mode:-0}" = 1 ]; then
        steam_args=(--steam)
        [ "''${app_g[mango]:-${if mangoApp then "1" else "0"}}" = 1 ] && mango_args=(--mangoapp)
      fi
      printf '%s %s %s %s' "$w" "$h" "$fps" "$hdr_on" >"$rt/sunshine-headless-gamescope-params"
      # Record the gamescope store path + argv so a stale one is restarted in `start`.
      printf '%s' "$(gamescope_marker_now)" >"$rt/sunshine-headless-gamescope-bin"

      gamescope_env="ENABLE_GAMESCOPE_WSI=1 PATH=${lib.optionalString mangoApp "${mangoappWrapper}/bin:"}${gamescopePkg}/bin"
      # --mangoapp is steam mode only, so a plain app gets no MANGOHUD_CONFIGFILE (the file
      # is written for steam-mode apps only, see the start verb).
      if [ "''${app_steam_mode:-0}" = 1 ] && [ "''${app_g[mango]:-${if mangoApp then "1" else "0"}}" = 1 ]; then
        gamescope_env="$gamescope_env MANGOHUD_CONFIGFILE=$rt/sunshine-mangoapp.conf"
      fi

      # Free the transient unit first: a leftover makes systemd-run refuse the name.
      rm -f "$rt/gamescope-0"
      systemctl --user reset-failed ${gamescopeUnit} 2>/dev/null || true
      stop_gamescope_unit
      # KillSignal=SIGKILL skips gamescope's destructor path on stop.
      systemd-run --user \
        --collect \
        --unit=${gamescopeUnit} \
        --property=Type=simple \
        --property=Restart=always \
        --property=KillSignal=SIGKILL \
        --property="ExecStopPost=$self drain gamescope" \
        --same-dir \
        --property="Environment=$gamescope_env" \
        "''${input_args[@]}" \
        -- "''${gscope_wrap[@]}" "''${gamescope_wrapper[@]}" "''${rt_args[@]}" \
            --backend headless \
            --expose-wayland \
            "''${steam_args[@]}" \
            --xwayland-count 2 \
            "''${mango_args[@]}" \
            "''${hdr_args[@]}" \
            "''${upscale_args[@]}" \
            -W "$w" -H "$h" -r "$fps" \
            -w "$rw" -h "$rh" \
            -- ${pkgs.coreutils}/bin/sleep infinity

      for _ in $(seq 1 300); do
        [ -S "$rt/gamescope-0" ] && break
        sleep 0.1
      done
      # Surface a launch failure instead of streaming a black frame.
      if [ ! -S "$rt/gamescope-0" ]; then
        echo "sunshine-headless: gamescope-0 never appeared within 30s of start_gamescope -W $w -H $h -r $fps (see: journalctl --user -u ${gamescopeUnit})" >&2
        exit 1
      fi
      sleep 1
    }
  '';

  hooks = {
    setup = ''
      case "$app_slug" in
      ${appCases}
      esac
    '';

    ensure = ''
      local client_w="$1" client_h="$2" client_fps="$3" client_hdr=0
      ${lib.optionalString mangoApp ''
        # gamescope reads the file through its own env; a plain app that loads MangoHud
        # in-process must not inherit it (Steam's hooks pass it in app_env themselves).
        if [ "''${app_steam_mode:-0}" = 1 ] && [ "''${app_g[mango]:-0}" = 1 ]; then
          printf 'no_display\n' >"$rt/sunshine-mangoapp.conf"
        fi
      ''}

      ${lib.optionalString hdr ''
        # An app with hdr = false must not advertise HDR to itself on an HDR client.
        if [ "''${app_g[hdr]:-0}" = 1 ]; then
          case "$4" in true | 1 | on) client_hdr=1 ;; esac
        fi
      ''}

      if [ -S "$rt/gamescope-0" ] && systemctl --user is-active --quiet ${gamescopeUnit}; then
        saved_params="$(cat "$rt/sunshine-headless-gamescope-params" 2>/dev/null || true)"
        saved_w="$(printf '%s' "$saved_params" | awk '{print $1}')"
        saved_h="$(printf '%s' "$saved_params" | awk '{print $2}')"
        saved_fps="$(printf '%s' "$saved_params" | awk '{print $3}')"
        saved_hdr="$(printf '%s' "$saved_params" | awk '{print $4}')"
        # A rebuilt gamescope (store path differs) must restart the stale one.
        saved_bin="$(cat "$rt/sunshine-headless-gamescope-bin" 2>/dev/null || true)"

        if [ -n "$client_w" ] && [ -n "$client_h" ] && [ -n "$client_fps" ] \
            && { [ "$saved_w" != "$client_w" ] || [ "$saved_h" != "$client_h" ] || [ "$saved_fps" != "$client_fps" ] || [ "$saved_hdr" != "$client_hdr" ] || [ "$saved_bin" != "$(gamescope_marker_now)" ]; }; then
          if streaming_active gamescope; then
            # Never restart gamescope under a live stream: another client is
            # capturing the current node, and stop_gamescope would kill it.
            echo "start: keeping gamescope (stream active); app joins at the current geometry" >&2
          else
            stop_gamescope
            start_gamescope "$client_w" "$client_h" "$client_fps" "$client_hdr"
          fi
        fi
      elif [ -n "$client_w" ] && [ -n "$client_h" ] && [ -n "$client_fps" ]; then
        start_gamescope "$client_w" "$client_h" "$client_fps" "$client_hdr"
      else
        start_gamescope "1920" "1080" "60" "$client_hdr"
      fi
      # Without them the app would land on whatever X server owns the hardcoded number.
      wait_gamescope_displays || exit 1
    '';

    appEnv = ''
      compositor_env+=(
        "DISPLAY=$gs_x0"
        "WAYLAND_DISPLAY=gamescope-0"
        "GAMESCOPE_WAYLAND_DISPLAY=gamescope-0"
        "ENABLE_GAMESCOPE_WSI=1"
      )
      if [ "''${app_g[native_wayland]:-${if nativeWayland then "1" else "0"}}" != 1 ]; then
        compositor_env+=("QT_QPA_PLATFORM=xcb")
      fi
    '';

    waitReady = ''
      wait_gamescope_displays || true
    '';

    tick = ''
      # Only gamescope --steam gates presentation on app ids.
      [ "$app_steam_mode" = 1 ] && app_present
    '';

    probe = ''
      if [ -S "$rt/gamescope-0" ] && systemctl --user is-active --quiet ${gamescopeUnit}; then
        probe_gamescope_stale || return 0
      fi
      start_gamescope "1" "1" "1" "0"
    '';

    recycle = ''
      local hb gone now hb_at age idle regrow gs_active params gone_at
      # 30s timer: tear the session down after session.idleTimeout without a stream, and
      # regrow the probe gamescope after gamescope.regrowTimeout with no gamescope at all.
      hb="$rt/sunshine-headless-stream-hb-gamescope"
      gone="$rt/sunshine-headless-gamescope-gone"
      if streaming_active gamescope; then
        touch "$hb" 2>/dev/null || true
        rm -f "$gone"
        return 0
      fi
      now="$(date +%s)"
      hb_at="$(stat -c %Y "$hb" 2>/dev/null || echo 0)"
      age=$(( now - hb_at ))
      local f recycle_idle=""
      for f in "$rt"/sunshine-headless-app-*.active; do
        [ -e "$f" ] || continue
        app_setup "$(cat "$f" 2>/dev/null || true)" 2>/dev/null || continue
        [ "$app_compositor" = gamescope ] || continue
        recycle_idle="$app_idle_timeout"
        break
      done
      idle="''${recycle_idle:-$session_idle_timeout}"
      regrow=${toString gamescopeRegrowTimeout}

      gs_active=0
      if [ -S "$rt/gamescope-0" ] && systemctl --user is-active --quiet ${gamescopeUnit}; then
        gs_active=1
      fi

      if [ "$gs_active" = 1 ]; then
        rm -f "$gone"
        # The minimal probe gamescope has nothing to tear down.
        params="$(cat "$rt/sunshine-headless-gamescope-params" 2>/dev/null || true)"
        if [ "$params" = "1 1 1 0" ]; then
          if probe_gamescope_stale; then
            start_gamescope "1" "1" "1" "0"
          fi
          return 0
        fi
        if [ "$idle" -gt 0 ] && [ "$age" -ge "$idle" ]; then
          recycle_stop_sessions gamescope
          stop_gamescope
        fi
        return 0
      fi

      # No gamescope at all: clean up a session orphaned by a gamescope crash.
      if [ "$idle" -gt 0 ] && [ "$age" -ge "$idle" ]; then
        recycle_stop_sessions gamescope
      fi
      [ "$regrow" -gt 0 ] || return 0
      # Regrow only serves the daemon's display probe; a stopped daemon opts out.
      systemctl --user is-active --quiet sunshine-headless.service || return 0
      gone_at="$(stat -c %Y "$gone" 2>/dev/null || true)"
      if [ -z "$gone_at" ]; then
        printf '%s\n' "$now" >"$gone"
        return 0
      fi
      if [ $(( now - gone_at )) -ge "$regrow" ]; then
        rm -f "$gone"
        start_gamescope "1" "1" "1" "0"
      fi
    '';
  };
}
