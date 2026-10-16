{ icedosLib, lib, ... }:

{
  options.icedos.gaming.unshade =
    let
      inherit (icedosLib) mkBoolOption;
      inherit (lib) importTOML;

      inherit ((importTOML ./config.toml).icedos.gaming.unshade)
        includeInIcedosGc
        ;
    in
    {
      includeInIcedosGc = mkBoolOption { default = includeInIcedosGc; };
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
          inherit (config.icedos.gaming) unshade;
          inherit (lib) getExe mkIf;
        in
        {
          nixpkgs.overlays = [
            (final: super: {
              unshade = final.callPackage ./package.nix {
                inherit (icedosLib.packaging) installDesktopEntry;
              };
            })
          ];

          environment.systemPackages = [ pkgs.unshade ];

          # Append a non-interactive shader-cache sweep before nh clean.
          icedos.system.gc.hooks.postGc = mkIf unshade.includeInIcedosGc [
            "${getExe pkgs.unshade} --all"
          ];

          icedos.system.tips.list = [
            "unshade clears out old game shader caches that pile up over time."
          ]
          ++ lib.optionals unshade.includeInIcedosGc [
            "icedos gc sweeps old game shader caches utilizing unshade."
          ];
        }
      )
    ];

  meta.name = "unshade";
}
