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
          inherit (lib) mkIf;

          unshadeGcHook = ''
            VDF="''${HOME}/.steam/steam/config/libraryfolders.vdf"
            [ -f "$VDF" ] || exit 0

            gc_section "''${HOME} (shader caches)" "shader cache"

            MESA_DIR="''${MESA_SHADER_CACHE_DIR:-$HOME/.cache/mesa_shader_cache}"
            if [ -d "$MESA_DIR" ]; then
              gc_del "$MESA_DIR"
            fi

            declare -a LIBRARIES=()
            while IFS= read -r line; do
              if [[ "$line" =~ \"path\"[[:space:]]*\"(.*)\" ]]; then
                LIBRARIES+=("''${BASH_REMATCH[1]}")
              fi
            done < "$VDF"

            for lib in "''${LIBRARIES[@]}"; do
              SP="$lib/steamapps"
              [ -d "$SP" ] || continue
              if [ -d "$SP/shadercache" ]; then
                gc_del "$SP/shadercache"
              fi
              while IFS= read -r -d $'\0' f; do
                gc_del "$f"
              done < <(find "$SP" \( -name "*.dxvk-cache" -o -name "*.vkd3d-cache" -o -name "*.vkd3d-cache.write" \) -print0 2>/dev/null)
            done

            if [ -d "''${HOME}/.cache/nvidia/GLCache" ]; then
              gc_del "''${HOME}/.cache/nvidia/GLCache"
            fi
            if [ -d "''${HOME}/.cache/radeon" ]; then
              gc_del "''${HOME}/.cache/radeon"
            fi
            exit 0
          '';
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

          # Non-interactive shader-cache sweep after nh clean.
          icedos.system.gc.hooks.postGc = mkIf unshade.includeInIcedosGc [
            unshadeGcHook
          ];

          icedos.system.tips.list = [
            "unshade clears out old game shader caches that pile up over time."
          ]
          ++ lib.optionals unshade.includeInIcedosGc [
            "icedos gc sweeps old game shader caches."
          ];
        }
      )
    ];

  meta.name = "unshade";
}
