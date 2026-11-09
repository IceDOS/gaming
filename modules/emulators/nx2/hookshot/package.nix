{
  appimageTools,
  buildFHSEnv,
  fetchurl,
  installDesktopEntry,
  lib,
  makeDesktopItem,
  makeWrapper,
  stdenvNoCC,
}:

let
  source = builtins.fromJSON (builtins.readFile ./source.json);
  pname = "hookshot";
  inherit (source) version;
  desktopFile = "hookshot-builder.desktop";

  contents =
    (appimageTools.extract {
      inherit pname version;
      src = fetchurl { inherit (source) url hash; };

      # copy2 keeps the store's read-only mode, which breaks overwriting copied assets on rebuilds.
      postExtract = ''
        substituteInPlace $out/usr/share/hookshot/nx2/make_game.py \
          --replace-fail 'shutil.copy2(icon, os.path.join(out, "hookshot.png"))' \
          'shutil.copyfile(icon, os.path.join(out, "hookshot.png"))' \
          --replace-fail 'shutil.copy2(src, os.path.join(work, "image", "chunks.txt"))' \
          'dst = os.path.join(work, "image", "chunks.txt"); os.remove(dst) if os.path.exists(dst) else None; shutil.copyfile(src, dst)'
      '';
    }).overrideAttrs
      (_: {
        icedosNoCache = true;
        preferLocalBuild = true;
        allowSubstitutes = false;
      });

  fhs = buildFHSEnv (
    appimageTools.defaultFhsEnvArgs
    // {
      pname = "hookshot-fhs";
      inherit version;
      runScript = "env";
    }
  );

  desktopItem = makeDesktopItem {
    name = "hookshot-builder";
    desktopName = "Hookshot Builder";
    comment = "Builds Ocarina of Time for PC from your own copy of the game";
    exec = "/@out@/bin/hookshot";
    icon = "hookshot";
    type = "Application";
    categories = [ "Game" ];

    actions.Play = {
      name = "Play";
      exec = "/@out@/bin/hookshot --play";
    };
  };
in
stdenvNoCC.mkDerivation {
  inherit pname version;

  dontUnpack = true;

  nativeBuildInputs = [ makeWrapper ];

  # The two HOOKSHOT_ variables keep the builder on this pin. APPIMAGE becomes builder= in each game folder.
  installPhase = ''
    runHook preInstall

    makeWrapper ${fhs}/bin/hookshot-fhs $out/bin/hookshot \
      --add-flags ${contents}/AppRun \
      --set HOOKSHOT_LATEST_TAG none \
      --set HOOKSHOT_LINUX_LIST ${contents}/hookshot-linux.txt \
      --set-default APPIMAGE /run/current-system/sw/bin/hookshot

    install -Dm644 ${contents}/hookshot.png $out/share/pixmaps/hookshot.png

    ${installDesktopEntry { inherit desktopItem desktopFile; }}

    runHook postInstall
  '';

  meta = {
    description = "Native PC recompilation of Ocarina of Time for Switch 2, built from your own copy";
    homepage = "https://github.com/NotRexed/Hookshot";
    license = lib.licenses.gpl3Plus;
    mainProgram = pname;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
