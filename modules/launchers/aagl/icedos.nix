{ lib, icedosLib, ... }:

{
  options.icedos.gaming.aagl =
    let
      inherit (lib) importTOML;

      inherit (icedosLib)
        mkStrListOption
        ;

      inherit ((importTOML ./config.toml).icedos.gaming.aagl)
        launchers
        ;
    in
    {
      launchers = mkStrListOption { default = launchers; };
    };

  inputs.aagl = {
    url = "github:ezKEa/aagl-gtk-on-nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs.nixosModules =
    { inputs, ... }:
    [
      inputs.aagl.nixosModules.default
      (
        {
          config,
          ...
        }:
        let
          inherit (config.icedos.gaming.aagl) launchers;
        in
        {
          nix.settings = inputs.aagl.nixConfig; # Set up Cachix

          programs = lib.listToAttrs (
            map (game: {
              name = game;
              value.enable = true;
            }) launchers # Adds launchers and /etc/hosts rules
          );
        }
      )
    ];

  meta.name = "aagl";
}
