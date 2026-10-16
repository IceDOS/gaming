{
  cmake,
  fetchFromGitHub,
  jq,
  libGL,
  libX11,
  libffi,
  libxext,
  libxfixes,
  libxkbcommon,
  pkg-config,
  stdenv,
  vulkan-headers,
  wayland,
  wayland-scanner,
}:

let
  # Refreshed by ./update.sh: bumps rev only on overlay-path changes and derives
  # vkroots lockstep with that rev's dxvk-nvapi submodule.
  source = builtins.fromJSON (builtins.readFile ./source.json);

  # GE builds against the vkroots its dxvk-nvapi submodule vendors; updater pins it.
  vkroots = fetchFromGitHub {
    owner = "misyltoad";
    repo = "vkroots";
    rev = source.vkrootsRev;
    hash = source.vkrootsHash;
  };
in
stdenv.mkDerivation (rec {
  pname = "steam-overlay-wayland";
  inherit (source) version;

  # Also yields lsteamclient_overlay_bridge, the runtime lib the layer links (add_subdirectory'd in).
  src = fetchFromGitHub {
    owner = "GloriousEggroll";
    repo = "proton-ge-custom";
    inherit (source) rev hash;
    # Same list the updater diffs against, so the two cannot drift.
    sparseCheckout = source.overlayPaths;
  };
  # The other overlay-path references below derive from the same list.
  sourceRoot = "source/${builtins.elemAt source.overlayPaths 0}";

  nativeBuildInputs = [
    cmake
    jq
    pkg-config
    wayland-scanner
  ];

  buildInputs = [
    libGL
    libX11
    libffi
    libxext
    libxfixes
    libxkbcommon
    vulkan-headers
    wayland
  ];

  cmakeFlags = [
    "-DCMAKE_BUILD_TYPE=release"
    "-DVKROOTS_INCLUDE_DIR=${vkroots}"
    "-DVULKAN_HEADERS_INCLUDE_DIR=${vulkan-headers}/include"
    "-DLSTEAMCLIENT_OVERLAY_BRIDGE_SOURCE_DIR=${src}/${builtins.elemAt source.overlayPaths 1}"
  ];

  postInstall = ''
    JSON=$out/share/vulkan/implicit_layer.d/VkLayer_GE_wayland_steam_overlay.json

    # Loader skips implicit layers without disable_environment; layer and bridge sit
    # side-by-side in $out/lib, resolved via $ORIGIN.
    jq --arg out "${placeholder "out"}" '
      .layer.library_path = ($out + "/lib/libVkLayer_GE_Wayland_SteamOverlay.so")
    ' "$JSON" > "$JSON.tmp" && mv "$JSON.tmp" "$JSON"
  '';

  # An unresolved bridge makes the loader silently drop the overlay; fail here
  # rather than ship a dead layer (the updater pushes unattended).
  doInstallCheck = true; # installCheckPhase must actually run
  installCheckPhase = ''
    # Take the soname from the layer's NEEDED entry so a soversion bump updates the check.
    needed=$(readelf -d "$out/lib/libVkLayer_GE_Wayland_SteamOverlay.so" \
      | sed -n 's/.*NEEDED.*\(liblsteamclient_overlay_bridge[^]]*\).*/\1/p' | head -1)
    test -n "$needed"
    test -f "$out/lib/$needed"
    # Capture first so a missing/broken ldd aborts via set -e; $ORIGIN resolves the bridge.
    ldd_out=$(ldd "$out/lib/libVkLayer_GE_Wayland_SteamOverlay.so")
    ! grep -q 'not found' <<<"$ldd_out"
  '';
})
