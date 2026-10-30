{
  bubblewrap,
  channel ? "stable",
  fetchurl,
  lib,
  makeDesktopItem,
  patchelf,
  python3,
  runtimeShell,
  squashfsTools,
  stdenv,
}:

let
  # Pins refreshed by ./update.sh, one per release channel.
  source = (builtins.fromJSON (builtins.readFile ./source.json)).${channel};

  desktopItem = makeDesktopItem {
    name = "bbport";
    desktopName = "Bloodborne";
    comment = "Native Bloodborne port launcher";
    exec = "bbport";
    icon = "applications-games";
    categories = [ "Game" ];
  };
in
stdenv.mkDerivation {
  pname = "bbport";
  inherit (source) version;

  src = fetchurl {
    inherit (source) url hash;
  };

  dontUnpack = true;

  nativeBuildInputs = [
    patchelf
    python3
    squashfsTools
  ];

  # BBSC's memory checks go through a shim that also accepts the game image (see lib/bbsc-vma.c).
  # The patched library sits in an overlay above the AppImage store, so the AppImage stays intact.
  buildPhase = ''
    runHook preBuild

    # The squashfs image starts where the runtime's ELF section headers end.
    offset=$(python3 -I -c '
    import struct, sys
    head = open(sys.argv[1], "rb").read(64)
    shoff, = struct.unpack_from("<Q", head, 0x28)
    shentsize, shnum = struct.unpack_from("<HH", head, 0x3A)
    print(shoff + shentsize * shnum)
    ' $src)
    unsquashfs -q -o "$offset" -d image $src \
      'nix/store/*-bbport-0.1/share/bbport/bin/gpu/libbbnet*.so'
    chmod -R u+w image
    gpu=$(echo image/nix/store/*-bbport-0.1/share/bbport/bin/gpu)
    # 0.7 renamed libbbnet.so to libbbnet20.so.
    net=$(echo $gpu/libbbnet*.so)
    # Each renamed import keeps its length, so the string tables are rewritten in place.
    # Releases whose BBSC lacks the checks leave the overlay empty.
    if python3 -I -c '
    import sys
    data = open(sys.argv[1], "rb").read()
    for old, new in [
        (b"\0runtime_memory_vma_info\0", b"\0bbport_bbsc_vma_info_v1\0"),
        (b"\0process_vm_readv\0", b"\0bbsc_vm_readv_v1\0"),
    ]:
        if old not in data:
            sys.exit(1)
        data = data.replace(old, new)
    open(sys.argv[1], "wb").write(data)
    ' $net; then
      $CC -O2 -shared -fPIC -o $gpu/libbbsc_vma.so ${./lib/bbsc-vma.c}
      # The renamed readv import still asks for GLIBC_2.15, which the shim does not define.
      patchelf --clear-symbol-version bbsc_vm_readv_v1 --add-needed libbbsc_vma.so $net
    else
      rm -r image/nix/store/*
    fi

    runHook postBuild
  '';

  # Stripping or patching the AppImage runtime would break the appended image.
  dontFixup = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 $src $out/libexec/bbport/Bloodborne-bbport-x86_64.AppImage
    mkdir -p $out/libexec/bbport/overlay
    cp -r image/nix/store/. $out/libexec/bbport/overlay/
    install -Dm755 ${./lib/wrapper.sh} $out/bin/bbport
    substituteInPlace $out/bin/bbport \
      --subst-var-by shell ${runtimeShell} \
      --subst-var-by bwrap ${lib.getExe bubblewrap} \
      --subst-var-by appimage $out/libexec/bbport/Bloodborne-bbport-x86_64.AppImage \
      --subst-var-by overlay $out/libexec/bbport/overlay
    install -Dm644 ${desktopItem}/share/applications/bbport.desktop -t $out/share/applications

    runHook postInstall
  '';

  meta = {
    description = "Native Linux port of Bloodborne (bring your own v1.09 dump)";
    homepage = "https://github.com/deadinside28/bloodborne_pc";
    license = lib.licenses.gpl2Only;
    mainProgram = "bbport";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
