{ callPackage, installDesktopEntry }:

# Shared with the other nx2 emulators. Pin refreshed by ./update.sh.
callPackage ../mk-package.nix {
  inherit installDesktopEntry;
  source = builtins.fromJSON (builtins.readFile ./source.json);
  pname = "lichii";
  appId = "io.github.zortos293.lichii";
  desktopName = "Lichii";
  comment = "Experimental Nintendo Switch and Switch 2 emulator";
  iconSize = "256x256";
  homepage = "https://github.com/zortos293/Lichii";
}
