{ icedosLib, ... }:

{
  outputs.nixosModules =
    { ... }:
    [
      (
        { pkgs, ... }:
        {
          nixpkgs.overlays = [
            (final: super: {
              lichii = final.callPackage ./package.nix {
                inherit (icedosLib.packaging) installDesktopEntry;
              };
            })
          ];

          environment.systemPackages = [ pkgs.lichii ];

          # Upstream's dist/72-eden-input.rules: logind grants users hidraw access to controllers.
          services.udev.extraRules = ''
            KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ENV{ID_INPUT_JOYSTICK}=="1", MODE="0660", TAG+="uaccess"
          '';
        }
      )
    ];

  meta.name = "lichii";
}
