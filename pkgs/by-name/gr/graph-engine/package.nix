{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  ninja,
  pkg-config,
  git,
  boost,
  libuuid,
  unilog,
  xir,
  vart,
  xrt,
}:

stdenv.mkDerivation rec {
  pname = "graph-engine";
  version = "1.0.0";

  src = fetchFromGitHub {
    owner = "amd";
    repo = "graph_engine";
    rev = "2410822ec0450ff3602ef26bbe074685765c9144";
    hash = "sha256-W9vtQ/wq6l0gT2B5w51NBK0AB6MG3dspZSzTqCzUMgU=";
  };

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
    git
  ];

  buildInputs = [
    boost
    libuuid
    unilog
    xir
    vart
    xrt
  ];

  cmakeFlags = [
    (lib.cmakeBool "BUILD_TEST" false)
    (lib.cmakeBool "BUILD_SHARED_LIBS" true)
    (lib.cmakeFeature "XRT_DIR" "${xrt}/opt/xilinx/xrt/share/cmake/XRT")
    (lib.cmakeFeature "CMAKE_PREFIX_PATH" "${xrt}/opt/xilinx/xrt")
  ];

  postPatch = ''
    # Create a fake git repo for version detection
    git init
    git config user.email "nix@build"
    git config user.name "Nix Build"
    git add -A
    git commit -m "Nix build" --allow-empty

    # Fix GCC 15 compatibility
    for f in $(find . -name "*.cpp" -o -name "*.hpp"); do
      if grep -q 'uint64_t\|int64_t\|uint32_t\|int32_t' "$f" 2>/dev/null; then
        if ! grep -q '#include <cstdint>' "$f" 2>/dev/null; then
          sed -i '1i #include <cstdint>' "$f"
        fi
      fi
    done
  '';

  meta = {
    description = "Graph execution engine for AMD Vitis AI";
    homepage = "https://github.com/amd/graph_engine";
    license = lib.licenses.asl20;
    platforms = [ "x86_64-linux" ];
    maintainers = with lib.maintainers; [ robcohen ];
  };
}
