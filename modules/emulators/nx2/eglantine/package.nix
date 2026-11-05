{ callPackage, installDesktopEntry }:

# Shared with the other nx2 emulators. Pin refreshed by ./update.sh.
callPackage ../mk-package.nix {
  inherit installDesktopEntry;
  source = builtins.fromJSON (builtins.readFile ./source.json);
  pname = "eglantine";
  appId = "dev.eglantine.eglantine";
  desktopName = "Eglantine";
  comment = "Experimental Nintendo Switch 2 emulator";
  iconSize = "512x512";
  homepage = "https://github.com/Djihads80/Eglantine";
}
