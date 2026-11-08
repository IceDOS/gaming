{ ... }:

{
  outputs.nixosModules =
    { ... }:
    [
      (
        { pkgs, ... }:
        {
          nixpkgs.overlays = [
            (final: super: {
              playdb-cnt = final.callPackage ./package.nix { };
            })
          ];

          environment.systemPackages = [ pkgs.playdb-cnt ];

          icedos.system.tips.list = [
            "play-duskbloods launches The Duskbloods Network Test in eglantine or lichii with local stand-in servers."
          ];
        }
      )
    ];

  meta.name = "playdb-cnt";
}
