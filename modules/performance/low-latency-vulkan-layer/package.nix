{
  cmake,
  fetchFromGitHub,
  stdenv,
  vulkan-headers,
  vulkan-loader,
  vulkan-utility-libraries,
}:

let
  # Pin refreshed by ./update.sh; `rev` is tracked separately from `version` so an
  # upstream tag-prefix change does not need a package edit.
  source = builtins.fromJSON (builtins.readFile ./source.json);
in
stdenv.mkDerivation {
  pname = "low-latency-vulkan-layer";
  inherit (source) version;

  src = fetchFromGitHub {
    owner = "Korthos-Software";
    repo = "low_latency_layer";
    inherit (source) rev hash;
  };

  nativeBuildInputs = [ cmake ];

  buildInputs = [
    vulkan-headers
    vulkan-loader
    vulkan-utility-libraries
  ];
}
