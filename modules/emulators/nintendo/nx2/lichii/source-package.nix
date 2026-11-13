{
  # From icedos.gaming.lichii.source.
  hash,
  patches,
  pgo,
  rev,
  version,

  SDL2,
  boost,
  llvmPackages_latest,
  cmake,
  cpp-jwt,
  cubeb,
  eden,
  enet,
  fetchFromGitHub,
  fetchpatch,
  ffmpeg-headless,
  fmt,
  frozen-containers,
  gamemode,
  glslang,
  httplib,
  installDesktopEntry,
  kdePackages,
  lib,
  libopus,
  libusb1,
  libva,
  lz4,
  makeDesktopItem,
  nlohmann_json,
  ninja,
  openssl,
  pipewire,
  pkg-config,
  python3,
  qt6,
  sdl3,
  simpleini,
  sirit,
  spirv-headers,
  spirv-tools,
  stb,
  stdenv,
  unordered_dense,
  vulkan-headers,
  vulkan-loader,
  vulkan-memory-allocator,
  vulkan-utility-libraries,
  wrapGAppsHook3,
  xbyak,
  zlib,
  zstd,
}:

let
  owner = "zortos293";
  repo = "Lichii";
  appId = "io.github.zortos293.lichii";
  desktopFile = "${appId}.desktop";

  extraPatches = map (p: fetchpatch { inherit (p) url hash excludes; }) patches;

  # Sources CPMUtil would download: DOWNLOAD_ONLY ones and zstd, which upstream always bundles.
  zstdSrc = fetchFromGitHub {
    owner = "facebook";
    repo = "zstd";
    rev = "33618c89e511637f8a6ef955b3501766d71feb53";
    hash = "sha256-UP99PUq8N+fmU972Jxim4f9u//T+4hRW+wuTZzWg3uI=";
  };

  zbic = fetchFromGitHub {
    owner = "kinnay";
    repo = "zbic";
    rev = "11b08f2712264bbed731545085cbd9702096ceb7";
    hash = "sha256-pHvxa1gkUvQo6mUgmLWtj1kcu01BLdGmttZyb8ZAj/o=";
  };

  xxhashSrc = fetchFromGitHub {
    owner = "Cyan4973";
    repo = "xxHash";
    rev = "v0.8.3";
    hash = "sha256-h6kohM+NxvQ89R9NEXZcYBG2wPOuB4mcyPfofKrx9wQ=";
  };

  # nextendo.cpp (#1344) needs the httplib::Params of the pinned 0.46, nixpkgs has a newer API.
  httplibSrc = fetchFromGitHub {
    owner = "yhirose";
    repo = "cpp-httplib";
    rev = "v0.46.0";
    hash = "sha256-Vzr51oo344jFNwmqdtLWxClJpuCTzmnMqXyLCz8UZj4=";
  };

  reshadeSrc = fetchFromGitHub {
    owner = "crosire";
    repo = "reshade";
    rev = "v6.8.0";
    hash = "sha256-K6QC7CLqy8M318n9WbuqGvcRF9g9abvDD/xbr7T+nXo=";
  };

  # The release CI builds the -pgo AppImage with clang and the repo's eglantine.profdata.
  stdenv' = if pgo then llvmPackages_latest.stdenv else stdenv;
  pgoFlags = "-fprofile-use=@src@/eglantine.profdata -Wno-backend-plugin -Wno-profile-instr-unprofiled -Wno-profile-instr-out-of-date";

  desktopItem = makeDesktopItem {
    name = appId;
    comment = "Experimental Nintendo Switch and Switch 2 emulator";
    desktopName = "Lichii";
    genericName = "Switch Emulator";
    exec = "/@out@/bin/lichii %f";
    icon = appId;
    startupWMClass = "lichii";
    type = "Application";

    categories = [
      "Game"
      "Emulator"
    ];

    mimeTypes = [
      "application/x-nx-nro"
      "application/x-nx-nso"
      "application/x-nx-nsp"
      "application/x-nx-xci"
    ];
  };
in
stdenv'.mkDerivation (finalAttrs: {
  pname = "lichii";
  inherit version;

  src = fetchFromGitHub {
    inherit
      owner
      repo
      rev
      hash
      ;
  };

  patches = extraPatches;

  reshade = stdenv.mkDerivation {
    pname = "lichii-reshade-src";
    version = "6.8.0";
    src = reshadeSrc;
    patches = [ "${finalAttrs.src}/.patch/reshade/0001-from-chars-fallback.patch" ];
    dontConfigure = true;
    dontBuild = true;
    installPhase = "cp -r . $out";
  };

  strictDeps = true;

  nativeBuildInputs = [
    cmake
    ninja
    glslang
    pkg-config
    python3
    spirv-tools
    qt6.qttools
    qt6.wrapQtAppsHook
    wrapGAppsHook3
  ]
  ++ lib.optional pgo llvmPackages_latest.bintools;

  buildInputs = [
    boost
    cpp-jwt
    cubeb
    enet
    ffmpeg-headless
    fmt
    frozen-containers
    gamemode
    httplib
    kdePackages.quazip
    libopus
    libusb1
    libva
    lz4
    nlohmann_json
    openssl
    qt6.qt5compat
    qt6.qtbase
    qt6.qtcharts
    qt6.qtmultimedia
    qt6.qtwayland
    qt6.qtwebengine
    SDL2
    sdl3
    simpleini
    sirit
    spirv-headers
    stb
    unordered_dense
    vulkan-headers
    vulkan-memory-allocator
    vulkan-utility-libraries
    xbyak
    zlib
    zstd
  ];

  cmakeFlags = [
    (lib.cmakeFeature "CMAKE_BUILD_TYPE" "Release")
    (lib.cmakeBool "BUILD_TESTING" false)
    (lib.cmakeBool "YUZU_TESTS" false)
    (lib.cmakeBool "YUZU_CMD" true)
    (lib.cmakeBool "YUZU_ROOM" false)
    (lib.cmakeBool "YUZU_ROOM_STANDALONE" false)
    (lib.cmakeBool "ENABLE_UPDATE_CHECKER" false)
    (lib.cmakeBool "USE_DISCORD_PRESENCE" false)
    (lib.cmakeBool "YUZU_ENABLE_COMPATIBILITY_REPORTING" false)
    (lib.cmakeBool "YUZU_DISABLE_LLVM" true)
    (lib.cmakeBool "YUZU_USE_QT_WEB_ENGINE" true)
    (lib.cmakeBool "YUZU_USE_QT_MULTIMEDIA" true)
    # Upstream #1541 renamed YUZU_* flags to LICHII_* for nx2.
    (lib.cmakeBool "LICHII_TESTS" false)
    (lib.cmakeBool "LICHII_CMD" true)
    (lib.cmakeBool "LICHII_ROOM" false)
    (lib.cmakeBool "LICHII_ROOM_STANDALONE" false)
    (lib.cmakeBool "LICHII_ENABLE_COMPATIBILITY_REPORTING" false)
    (lib.cmakeBool "LICHII_DISABLE_LLVM" true)
    (lib.cmakeBool "LICHII_USE_QT_WEB_ENGINE" true)
    (lib.cmakeBool "LICHII_USE_QT_MULTIMEDIA" true)
    # New compilers warn where upstream's CI compiler does not.
    (lib.cmakeBool "ENABLE_WERROR" false)

    (lib.cmakeBool "CPMUTIL_FORCE_SYSTEM" true)
    (lib.cmakeFeature "YUZU_TZDB_PATH" "${eden.nx_tzdb}")
    (lib.cmakeFeature "LICHII_TZDB_PATH" "${eden.nx_tzdb}")
    (lib.cmakeFeature "zstd_CUSTOM_DIR" "${zstdSrc}")
    (lib.cmakeBool "zbic_FORCE_BUNDLED" true)
    (lib.cmakeFeature "zbic_CUSTOM_DIR" "${zbic}")
    (lib.cmakeBool "xxhash_FORCE_BUNDLED" true)
    (lib.cmakeFeature "xxhash_CUSTOM_DIR" "${xxhashSrc}")
    (lib.cmakeBool "httplib_FORCE_BUNDLED" true)
    (lib.cmakeFeature "httplib_CUSTOM_DIR" "${httplibSrc}")
    (lib.cmakeBool "reshade_FORCE_BUNDLED" true)
    (lib.cmakeFeature "reshade_CUSTOM_DIR" "${finalAttrs.reshade}")

    (lib.cmakeFeature "LICHII_BUILD_TAG" version)
    (lib.cmakeFeature "LICHII_BUILD_PLATFORM" "linux-x86_64${lib.optionalString pgo "-pgo"}-nix")
  ]
  ++ lib.optionals pgo [
    (lib.cmakeFeature "CMAKE_EXE_LINKER_FLAGS" "-fuse-ld=lld")
  ];

  preConfigure = lib.optionalString pgo ''
    cmakeFlagsArray+=(
      "-DCMAKE_C_FLAGS=${lib.replaceStrings [ "@src@" ] [ "$PWD" ] pgoFlags}"
      "-DCMAKE_CXX_FLAGS=${lib.replaceStrings [ "@src@" ] [ "$PWD" ] pgoFlags}"
    )
  '';

  dontWrapGApps = true;

  preFixup = ''
    qtWrapperArgs+=(
      "''${gappsWrapperArgs[@]}"
      --prefix LD_LIBRARY_PATH : ${
        lib.makeLibraryPath [
          vulkan-loader
          pipewire
        ]
      }
    )
  '';

  postInstall = ''
    if [ -e $out/bin/eden-cli ]; then
      mv $out/bin/eden-cli $out/bin/lichii-cli
    fi

    rm -f $out/share/applications/*.desktop
    ${installDesktopEntry { inherit desktopItem desktopFile; }}
  '';

  passthru = { inherit extraPatches; };

  meta = {
    description = "Experimental Nintendo Switch and Switch 2 emulator";
    homepage = "https://github.com/zortos293/Lichii";
    license = lib.licenses.gpl3Plus;
    mainProgram = "lichii";
    platforms = [ "x86_64-linux" ];
  };
})
