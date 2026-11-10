{ icedosLib, lib }:

let
  inherit (icedosLib)
    mkBoolOption
    mkEnumOption
    mkFloatBetweenOption
    mkIntBetweenOption
    ;

  inherit (lib) importTOML;

  gamescope = (importTOML ./config.toml).icedos.gaming.gamescope.sunshine-headless;
in
{
  # Gamescope --rt (realtime SCHED_FIFO; needs the cap_sys_nice wrapper). Off = only SetNice(-20).
  realtime = mkBoolOption { default = gamescope.realtime; };

  # Each patch forces a local rebuild, so each is its own option; even all-off is
  # still rebuilt (gamescopePkg's always-on overlay postPatch).
  preferDiscreteGpu = mkBoolOption { default = gamescope.preferDiscreteGpu; };

  # Prefer DMA-BUF buffers for the capture stream (fallback to SHM when the consumer can't).
  preferDmaBuf = mkBoolOption { default = gamescope.preferDmaBuf; };

  # HDR-capable gamescope (HDR/colorimetry patches); stream HDR follows the client per-stream.
  hdr = mkBoolOption { default = gamescope.hdr; };

  # Render Proton Wayland games natively (instead of via Xwayland).
  nativeWayland = mkBoolOption { default = gamescope.nativeWayland; };

  # Forward Moonlight keyboard/mouse (Sunshine's libvirtualhid devices) and composite the X cursor into
  # the stream. Host devices never leak in; don't stream from the primary daemon concurrently (same names).
  inputInjection = mkBoolOption { default = gamescope.inputInjection; };

  # Color management: Steam's Display color controls.
  colorManagement = mkBoolOption { default = gamescope.colorManagement; };

  # MangoHud overlay: --mangoapp on the gamescope used by the session.
  mangoApp = mkBoolOption { default = gamescope.mangoApp; };

  # Gamescope render size, upscaled to output; 0 renders at the output resolution.
  renderWidth = mkIntBetweenOption {
    path = "icedos.gaming.gamescope.sunshine-headless.renderWidth";
    source = ./config.toml;
    default = gamescope.renderWidth;
  } 0 8192;

  renderHeight = mkIntBetweenOption {
    path = "icedos.gaming.gamescope.sunshine-headless.renderHeight";
    source = ./config.toml;
    default = gamescope.renderHeight;
  } 0 8192;

  # SDR-on-HDR tuning: brightness (--hdr-sdr-content-nits) and gamut stretch.
  sdrContentNits = mkIntBetweenOption {
    path = "icedos.gaming.gamescope.sunshine-headless.sdrContentNits";
    source = ./config.toml;
    default = gamescope.sdrContentNits;
  } 0 10000;

  sdrGamutWideness = mkFloatBetweenOption {
    path = "icedos.gaming.gamescope.sunshine-headless.sdrGamutWideness";
    source = ./config.toml;
    default = gamescope.sdrGamutWideness;
  } 0 1;

  # Gamescope upscaler (-F) and sharpness (--fsr-sharpness; fsr/nis only).
  upscaleFilter =
    mkEnumOption
      {
        path = "icedos.gaming.gamescope.sunshine-headless.upscaleFilter";
        source = ./config.toml;
        default = gamescope.upscaleFilter;
      }
      [
        ""
        "fsr"
        "nis"
        "linear"
        "nearest"
        "pixel"
      ];

  fsrSharpness = mkIntBetweenOption {
    path = "icedos.gaming.gamescope.sunshine-headless.fsrSharpness";
    source = ./config.toml;
    default = gamescope.fsrSharpness;
  } 0 20;

  # Seconds with no gamescope at all (teardown, crash, manual stop) before the minimal
  # 1x1x1 probe gamescope is rerun so Sunshine's display probe keeps passing. 0 = off.
  regrowTimeout = mkIntBetweenOption {
    path = "icedos.gaming.gamescope.sunshine-headless.regrowTimeout";
    source = ./config.toml;
    default = gamescope.regrowTimeout;
  } 0 86400;
}
