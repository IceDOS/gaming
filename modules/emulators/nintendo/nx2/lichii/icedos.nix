{ icedosLib, lib, ... }:

{
  options.icedos.gaming.lichii =
    let
      inherit (lib) importTOML;

      inherit (icedosLib)
        mkBoolOption
        mkEnumOption
        mkStrListOption
        mkStrOption
        mkSubmoduleListOption
        mkSubmoduleOption
        ;

      inherit ((importTOML ./config.toml).icedos.gaming.lichii) build source;
    in
    {
      build =
        mkEnumOption
          {
            path = "icedos.gaming.lichii.build";
            source = ./config.toml;
            default = build;
          }
          [
            "appimage"
            "source"
          ];

      source = mkSubmoduleOption { default = { }; } {
        rev = mkStrOption { default = source.rev; };
        hash = mkStrOption { default = source.hash; };
        version = mkStrOption { default = source.version; };
        pgo = mkBoolOption { default = source.pgo; };

        patches = mkSubmoduleListOption { default = source.patches; } {
          url = mkStrOption { };
          hash = mkStrOption { };
          excludes = mkStrListOption { default = [ ]; };
        };
      };
    };

  outputs.nixosModules =
    { ... }:
    [
      (
        { config, pkgs, ... }:
        let
          inherit (lib) match substring;
          inherit (icedosLib) validate;
          cfg = config.icedos.gaming.lichii;
          src = cfg.source;
          isCommit = match "[0-9a-f]{40}" src.rev != null;

          # True, or throws when build = "source" has no rev.
          revSet = validate.abort {
            when = cfg.build == "source" && src.rev == "";
            path = "icedos.gaming.lichii.source.rev";
            msg = ''build = "source" needs a commit SHA or tag'';
          };

          lichiiSource = {
            inherit (src) rev hash pgo;
            patches = map (p: { inherit (p) url hash excludes; }) src.patches;

            version =
              if src.version != "" then
                src.version
              else if isCommit then
                "nx2-${substring 0 10 src.rev}"
              else
                src.rev;

            inherit (icedosLib.packaging) installDesktopEntry;
          };
        in
        {
          nixpkgs.overlays = [
            (final: super: {
              lichii =
                if cfg.build == "source" && revSet then
                  final.callPackage ./source-package.nix lichiiSource
                else
                  final.callPackage ./package.nix {
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
