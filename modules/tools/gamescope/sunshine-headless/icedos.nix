{ icedosLib, lib, ... }:

{
  options.icedos.gaming.gamescope.sunshine-headless = import ./options.nix {
    inherit icedosLib lib;
  };

  outputs.nixosModules =
    { inputs, ... }:
    [
      (
        {
          config,
          lib,
          pkgs,
          ...
        }:

        let
          headless = config.icedos.applications.sunshine-headless;
          cfg = config.icedos.gaming.gamescope.sunshine-headless;

          defaultCompositor =
            if headless.session.defaultCompositor != "" then
              headless.session.defaultCompositor
            else
              "gamescope";

          # A slug keys shell function names and runtime paths, so keep it [a-z0-9_].
          mkSlug =
            name:
            let
              mapped = lib.concatMapStrings (c: if builtins.match "[a-z0-9]" c != null then c else "_") (
                lib.stringToCharacters (lib.toLower name)
              );
              # Runs of underscores would otherwise survive a single replacement pass.
              collapse =
                s:
                if builtins.match "(.*)__(.*)" s == null then
                  s
                else
                  collapse (builtins.replaceStrings [ "__" ] [ "_" ] s);
            in
            collapse mapped;

          gamescopeApps = lib.filter (
            app: (if app.compositor != "" then app.compositor else defaultCompositor) == "gamescope"
          ) headless.apps;

          # Null per-app overrides inherit the backend-global value.
          apps = map (
            app:
            app
            // {
              slug = if app.slug != "" then app.slug else mkSlug app.name;
              gamescope = lib.mapAttrs (k: v: if v == null then cfg.${k} else v) app.gamescope;
            }
          ) gamescopeApps;

          packages = import ./packages.nix {
            inherit
              pkgs
              lib
              icedosLib
              inputs
              apps
              ;
            gamescope = cfg;
          };
        in
        {
          icedos.applications.sunshine-headless.compositors.gamescope = import ./scripts.nix {
            inherit
              pkgs
              lib
              cfg
              apps
              ;
            inherit (packages)
              gamescopePkg
              xnudge
              xdg-desktop-portal-gamescope
              sunshinePortalConfig
              ;
          };

          security.wrappers.sunshine-headless-gamescope = {
            owner = "root";
            group = "root";
            source = "${packages.gamescopePkg}/bin/gamescope";
            capabilities = "cap_sys_nice+pie";
          };

          assertions = [
            {
              # These four select a patched gamescope/wrapper at build time, so an app can
              # only turn them ON when the module-global option built them. Off always works.
              assertion = lib.all (
                app:
                lib.all (k: app.gamescope.${k} != true || cfg.${k}) [
                  "hdr"
                  "nativeWayland"
                  "inputInjection"
                  "mangoApp"
                ]
              ) apps;
              message = "icedos.applications.sunshine-headless.apps[].gamescope can only enable hdr/nativeWayland/inputInjection/mangoApp when the matching icedos.gaming.gamescope.sunshine-headless.* option is also true (each selects a patched gamescope or wrapper at build time).";
            }
            {
              # Steam's environment is built at evaluation time from the module globals
              # (see steam-headless/hooks.nix), so a per-app value would be ignored there.
              assertion = lib.all (
                app: !app.steamMode || (app.gamescope.mangoApp == null && app.gamescope.nativeWayland == null)
              ) gamescopeApps;
              message = "icedos.applications.sunshine-headless.apps[].gamescope.nativeWayland/mangoApp are ignored for a steamMode app: set icedos.gaming.gamescope.sunshine-headless instead.";
            }
          ];
        }
      )
    ];

  meta = {
    name = "sunshine-headless-gamescope";

    dependencies = [
      {
        url = "github:icedos/apps";
        modules = [
          "sunshine-headless"
        ];
      }
      {
        url = "github:icedos/providers";
        modules = [
          "jovian"
        ];
      }
    ];
  };
}
