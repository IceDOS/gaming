{ ... }:

{
  outputs.nixosModules =
    { ... }:
    [
      (
        { pkgs, ... }:
        let
          base = pkgs.callPackage ./package.nix { };
        in
        {
          environment.systemPackages = [ base ];

          # steam-runtime-tools scans the FHS /etc path; the NixOS loader has its
          # sysconfdir at /run/opengl-driver/share and never looks in /etc.
          environment.etc."vulkan/implicit_layer.d/VkLayer_GE_wayland_steam_overlay.json".source =
            "${base}/share/vulkan/implicit_layer.d/VkLayer_GE_wayland_steam_overlay.json";

          icedos.system.tips.list = [
            "Shift+Tab opens the Steam overlay in Wayland games as well."
          ];
        }
      )
    ];

  meta.name = "steam-wayland-overlay";
}
