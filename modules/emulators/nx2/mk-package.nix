{
  # Per-emulator values, set by each module's package.nix.
  appId,
  comment,
  desktopName,
  homepage,
  iconSize,
  pname,
  source,

  appimageTools,
  buildFHSEnv,
  fetchurl,
  gamemode,
  installDesktopEntry,
  lib,
  libgpg-error,
  makeDesktopItem,
  makeWrapper,
  stdenvNoCC,
}:

let
  inherit (source) version;

  desktopFile = "${appId}.desktop";

  contents = (appimageTools.extract {
    inherit pname version;
    src = fetchurl { inherit (source) url hash; };
  }).overrideAttrs (_: {
    icedosNoCache = true;
    preferLocalBuild = true;
    allowSubstitutes = false;
  });

  # Generic env instead of wrapType2, which only runs AppRun and so cannot start eden-cli.
  fhs = buildFHSEnv (
    appimageTools.defaultFhsEnvArgs
    // {
      pname = "${pname}-fhs";
      inherit version;
      runScript = "env";

      targetPkgs =
        pkgs:
        appimageTools.defaultFhsEnvArgs.targetPkgs pkgs
        ++ [
          # dlopened at runtime, so linuxdeploy did not bundle it.
          gamemode.lib
          # Bundled libgcrypt needs it, and the default FHS env lacks it.
          libgpg-error
        ];
    }
  );

  desktopItem = makeDesktopItem {
    name = appId;
    inherit comment desktopName;
    genericName = "Switch Emulator";
    exec = "/@out@/bin/${pname} %f";
    icon = appId;
    startupWMClass = pname;
    type = "Application";

    categories = [
      "Game"
      "Emulator"
    ];

    mimeTypes = [
      "application/x-nx-nro"
      "application/x-nx-nso"
      "application/x-nx-nsp"
      "application/x-nx-xci"
    ];
  };
in
stdenvNoCC.mkDerivation {
  inherit pname version;

  dontUnpack = true;

  nativeBuildInputs = [ makeWrapper ];

  # The AppImage bundles its own Qt, and Plasma points QT_PLUGIN_PATH at the system Qt plugins.
  installPhase = ''
    runHook preInstall

    makeWrapper ${fhs}/bin/${pname}-fhs $out/bin/${pname} \
      --unset QT_PLUGIN_PATH \
      --add-flags ${contents}/usr/bin/${pname}

    # Forks all ship bin/eden-cli, so publish it under a name that cannot collide.
    makeWrapper ${fhs}/bin/${pname}-fhs $out/bin/${pname}-cli \
      --unset QT_PLUGIN_PATH \
      --add-flags ${contents}/usr/bin/eden-cli

    install -Dm644 ${contents}/usr/share/icons/hicolor/${iconSize}/apps/${appId}.png \
      $out/share/icons/hicolor/${iconSize}/apps/${appId}.png

    ${installDesktopEntry { inherit desktopItem desktopFile; }}

    runHook postInstall
  '';

  meta = {
    description = comment;
    inherit homepage;
    license = lib.licenses.gpl3Plus;
    mainProgram = pname;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
