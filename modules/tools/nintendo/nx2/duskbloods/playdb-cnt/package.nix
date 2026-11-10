{
  copyDesktopItems,
  fetchFromGitHub,
  lib,
  makeDesktopItem,
  makeWrapper,
  python3,
  stdenvNoCC,
}:

let
  # Pin refreshed by ./update.sh.
  source = builtins.fromJSON (builtins.readFile ./source.json);

  python = python3.withPackages (ps: [
    ps.cryptography
    ps.grpcio
    ps.tkinter
  ]);
in
stdenvNoCC.mkDerivation {
  pname = "playdb-cnt";
  inherit (source) version;

  icedosNoCache = true;
  preferLocalBuild = true;
  allowSubstitutes = false;

  src = fetchFromGitHub {
    owner = "sikoGD";
    repo = "playDB-CNT";
    inherit (source) rev hash;
  };

  nativeBuildInputs = [
    copyDesktopItems
    makeWrapper
  ];

  # The launcher keeps its settings beside the script, which is read-only in the store.
  postPatch = ''
    substituteInPlace play_duskbloods.py \
      --replace-fail "SETTINGS = HERE / 'launcher_settings.json'" \
        "SETTINGS = Path(os.environ.get('XDG_CONFIG_HOME') or Path.home() / '.config') / 'playdb-cnt' / 'launcher_settings.json'" \
      --replace-fail "        SETTINGS.write_text(" \
        "        SETTINGS.parent.mkdir(parents=True, exist_ok=True); SETTINGS.write_text("
  '';

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    share=$out/share/playdb-cnt
    mkdir -p $share
    cp -r play_duskbloods.py tools assets $share/
    install -Dm644 assets/icon.png $out/share/icons/hicolor/256x256/apps/playdb-cnt.png

    makeWrapper ${python}/bin/python3 $out/bin/play-duskbloods \
      --add-flags "$share/play_duskbloods.py"

    runHook postInstall
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "playdb-cnt";
      desktopName = "Play Duskbloods";
      comment = "Launcher for The Duskbloods Network Test on Switch 2 emulators";
      exec = "play-duskbloods";
      icon = "playdb-cnt";
      categories = [ "Game" ];
    })
  ];

  meta = {
    description = "Launcher for The Duskbloods Network Test with local stand-in online servers";
    homepage = "https://github.com/sikoGD/playDB-CNT";
    mainProgram = "play-duskbloods";
    platforms = lib.platforms.linux;
  };
}
