{ ... }:

{
  outputs.nixosModules =
    { ... }:
    [
      (
        { pkgs, ... }:
        {
          boot = {
            kernelModules = [ "ntsync" ];

            kernelParams = [
              "clearcpuid=514" # Disables UMIP which fixes certain games from crashing on launch
            ];

            kernel.sysctl = {
              "kernel.split_lock_mitigate" = 0; # Fixes some games from stuttering
              "vm.max_map_count" = 2147483642; # SteamOS/Bazzite standard to prevent game map exhaustion
            };
          };

          security.pam.loginLimits = [
            {
              domain = "*";
              type = "hard";
              item = "memlock";
              value = "2147483648";
            }

            {
              domain = "*";
              type = "soft";
              item = "memlock";
              value = "2147483648";
            }
          ];

          services.udev.packages = with pkgs; [ game-devices-udev-rules ];

          icedos.system.tips.list = [
            "Game controllers, wheels and flight sticks work as soon as you plug them in."
            "Windows games run through Proton with less overhead here."
            "Games can use far more memory before the system stops them."
            "Known causes of game crashes and stutter are already switched off for you."
          ];
        }
      )
    ];

  meta.name = "tweaks";
}
