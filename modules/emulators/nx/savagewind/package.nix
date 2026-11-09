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
  pname = "savagewind";
  inherit (source) version;
  desktopFile = "savagewind.desktop";

  contents =
    (appimageTools.extract {
      inherit pname version;
      src = fetchurl { inherit (source) url hash; };
    }).overrideAttrs
      (_: {
        icedosNoCache = true;
        preferLocalBuild = true;
        allowSubstitutes = false;
      });

  fhs = buildFHSEnv (
    appimageTools.defaultFhsEnvArgs
    // {
      pname = "savagewind-fhs";
      inherit version;
      runScript = "env";
    }
  );

  desktopItem = makeDesktopItem {
    name = "savagewind";
    desktopName = "Savage Wind";
    comment = "Native PC recompilation of Breath of the Wild, built from your own copy";
    exec = "/@out@/bin/savagewind";
    icon = "savagewind";
    type = "Application";
    categories = [ "Game" ];

    actions.Configuration = {
      name = "Savage Wind Configuration";
      exec = "/@out@/bin/savagewind --config";
    };
  };
in
stdenvNoCC.mkDerivation {
  inherit pname version;

  dontUnpack = true;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    makeWrapper ${fhs}/bin/savagewind-fhs $out/bin/savagewind \
      --add-flags ${contents}/AppRun

    install -Dm644 ${contents}/savagewind.png $out/share/pixmaps/savagewind.png

    ${installDesktopEntry { inherit desktopItem desktopFile; }}

    runHook postInstall
  '';

  meta = {
    description = "Native PC recompilation of Breath of the Wild for Switch, built from your own copy";
    homepage = "https://github.com/Revivedx/SavageWindRecomp";
    license = lib.licenses.mit;
    mainProgram = pname;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
