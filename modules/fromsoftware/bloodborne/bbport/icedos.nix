{ icedosLib, lib, ... }:

{
  options.icedos.gaming.bbport =
    let
      inherit ((lib.importTOML ./config.toml).icedos.gaming.bbport) prerelease;
    in
    {
      prerelease = icedosLib.mkBoolOption { default = prerelease; };
    };

  outputs.nixosModules =
    { ... }:
    [
      (
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          inherit (config.icedos.gaming.bbport) prerelease;
        in
        {
          nixpkgs.overlays = [
            (final: super: {
              bbport = final.callPackage ./package.nix {
                channel = if prerelease then "prerelease" else "stable";
              };
            })
          ];

          environment.systemPackages = [ pkgs.bbport ];

          icedos.system.tips.list = lib.optionals prerelease [
            "You are on bbport prereleases: fixes arrive early, but things can break."
          ];
        }
      )
    ];

  meta.name = "bbport";
}
