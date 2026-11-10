{ lib, icedosLib, ... }:

{
  options.icedos.gaming.gamescope =
    let
      inherit ((fromTOML (lib.readFile ./config.toml)).icedos.gaming.gamescope) capSysNice wsi;
    in
    {
      capSysNice = icedosLib.mkBoolOption { default = capSysNice; };
      wsi = icedosLib.mkBoolOption { default = wsi; };
    };

  outputs.nixosModules =
    { ... }:
    [
      (
        {
          config,
          ...
        }:

        {
          programs.gamescope = {
            enable = true;
            capSysNice = config.icedos.gaming.gamescope.capSysNice;
            enableWsi = config.icedos.gaming.gamescope.wsi;
          };
        }
      )
    ];

  meta.name = "gamescope";
}
