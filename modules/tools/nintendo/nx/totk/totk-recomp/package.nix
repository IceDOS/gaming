{
  appimageTools,
  buildFHSEnv,
  fetchurl,
  gnused,
  installDesktopEntry,
  jq,
  lib,
  makeDesktopItem,
  makeWrapper,
  stdenvNoCC,
  writeShellScript,
}:

let
  source = builtins.fromJSON (builtins.readFile ./source.json);
  pname = "totk-recomp";
  inherit (source) version;
  desktopFile = "totk-recomp-setup.desktop";
  fhsArgs = appimageTools.defaultFhsEnvArgs;

  contents =
    (appimageTools.extract {
      inherit pname version;
      src = fetchurl { inherit (source) url hash; };

      # copy2 keeps the store's read-only mode, which breaks overwriting copied files on rebuilds.
      postExtract = ''
        substituteInPlace $out/tools/build_game.py \
          --replace-fail 'shutil.copy2(dll, exe.parent / dll.name)' \
          '(exe.parent / dll.name).unlink(missing_ok=True); shutil.copyfile(dll, exe.parent / dll.name)'
        substituteInPlace $out/installer/steps.py \
          --replace-fail 'shutil.copy2(src, tmp)' \
          'tmp.unlink(missing_ok=True); shutil.copy2(src, tmp); os.chmod(tmp, os.stat(tmp).st_mode | 0o200)'
        substituteInPlace $out/installer/recent.py \
          --replace-fail "return Path(base) / 'totk-recomp' / 'setup.json'" \
          "return Path(base) / 'icedos' / 'totk-recomp' / 'setup.json'"
      '';
    }).overrideAttrs
      (_: {
        icedosNoCache = true;
        preferLocalBuild = true;
        allowSubstitutes = false;
      });

  fhs = buildFHSEnv (
    fhsArgs
    // {
      pname = "totk-recomp-fhs";
      inherit version;
      runScript = "env";
      targetPkgs = pkgs: (fhsArgs.targetPkgs pkgs) ++ [ pkgs.libdecor ];
    }
  );

  # rebuild.txt keeps the release's store path, so point it at this package before each start.
  play = writeShellScript "totk-recomp-play" ''
    state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/icedos/totk-recomp"
    legacy_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/totk-recomp" # legacy path pre-2026-11
    if [ ! -e "$state_dir" ] && [ -d "$legacy_dir" ]; then
      mkdir -p "$(dirname "$state_dir")"
      mv "$legacy_dir" "$state_dir"
    elif [ -d "$state_dir" ] && [ -d "$legacy_dir" ]; then
      echo "totk-recomp: legacy state dir $legacy_dir ignored" >&2
    fi

    state="$state_dir/setup.json"
    dest="''${TOTK_RECOMP_DIR:-}"

    if [ -z "$dest" ] && [ -f "$state" ]; then
      dest="$(${jq}/bin/jq -r '.dest // empty' "$state")"
    fi

    if [ -z "$dest" ] || [ ! -x "$dest/totk" ]; then
      echo "totk-recomp: no install found. Run totk-recomp and finish the setup first." >&2
      exit 1
    fi

    rebuild="$dest/build-cache/rebuild.txt"

    if [ -f "$rebuild" ]; then
      ${gnused}/bin/sed -i -E 's#/nix/store/[^/]+-extracted#${contents}#g' "$rebuild"
    fi

    export PYTHONDONTWRITEBYTECODE=1
    export TCL_LIBRARY=${contents}/python/lib/tcl9.0
    export TK_LIBRARY=${contents}/python/lib/tk9.0
    cd "$dest"
    exec ./totk "$@"
  '';

  run = writeShellScript "totk-recomp-run" ''
    export PYTHONNOUSERSITE=1

    state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/icedos/totk-recomp"
    legacy_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/totk-recomp" # legacy path pre-2026-11
    if [ ! -e "$state_dir" ] && [ -d "$legacy_dir" ]; then
      mkdir -p "$(dirname "$state_dir")"
      mv "$legacy_dir" "$state_dir"
    elif [ -d "$state_dir" ] && [ -d "$legacy_dir" ]; then
      echo "totk-recomp: legacy state dir $legacy_dir ignored" >&2
    fi

    if [ "''${1:-}" = "--play" ]; then
      shift
      exec ${play} "$@"
    fi

    exec ${contents}/AppRun "$@"
  '';

  desktopItem = makeDesktopItem {
    name = "totk-recomp-setup";
    desktopName = "TotK Recomp Setup";
    comment = "Builds Tears of the Kingdom for this PC from your own game files";
    exec = "/@out@/bin/totk-recomp";
    icon = "totk-recomp";
    type = "Application";
    categories = [ "Game" ];

    actions.Play = {
      name = "Play";
      exec = "/@out@/bin/totk-recomp --play";
    };
  };
in
stdenvNoCC.mkDerivation {
  inherit pname version;

  dontUnpack = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    makeWrapper ${fhs}/bin/totk-recomp-fhs $out/bin/totk-recomp \
      --add-flags ${run}

    install -Dm644 ${contents}/totk-setup.png $out/share/pixmaps/totk-recomp.png

    ${installDesktopEntry { inherit desktopItem desktopFile; }}

    runHook postInstall
  '';

  meta = {
    description = "Native PC recompilation of Tears of the Kingdom, built from your own copy";
    homepage = "https://github.com/valentderah/totk-pc-recomp";
    license = lib.licenses.mit;
    mainProgram = pname;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
