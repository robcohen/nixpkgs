{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  ninja,
  pkg-config,
  git,
  protobuf,
  abseil-cpp,
  boost,
  glog,
  unilog,
  xir,
  target-factory,
}:

stdenv.mkDerivation rec {
  pname = "vart";
  version = "3.5.0";

  src = fetchFromGitHub {
    owner = "amd";
    repo = "vart";
    rev = "dafd687831e817720f430e6f6033f5f2cd78fe5b";
    hash = "sha256-nzt9D9jC7V2DSWHYZbmxesCmZN2Gc3CFanzpM0T6lUI=";
  };

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
    git
    protobuf
  ];

  buildInputs = [
    protobuf
    abseil-cpp
    boost
    glog
    unilog
    xir
    target-factory
  ];

  cmakeFlags = [
    (lib.cmakeBool "BUILD_TEST" false)
    (lib.cmakeBool "BUILD_PYTHON" false)
    (lib.cmakeBool "BUILD_SHARED_LIBS" true)
    (lib.cmakeBool "ENABLE_CPU_RUNNER" false)
    (lib.cmakeBool "ENABLE_SIM_RUNNER" false)
    (lib.cmakeBool "ENABLE_DPU_RUNNER" false)
    (lib.cmakeBool "ENABLE_XRNN_RUNNER" false)
  ];

  postPatch = ''
    # Remove -Werror
    substituteInPlace cmake/VitisCommon.cmake \
      --replace-fail "-Werror" ""

    # Create a fake git repo for version detection
    git init
    git config user.email "nix@build"
    git config user.name "Nix Build"
    git add -A
    git commit -m "Nix build" --allow-empty

    # Fix GCC 15 compatibility - add missing includes
    for f in $(find . -name "*.cpp" -o -name "*.hpp"); do
      if grep -q 'uint64_t\|int64_t\|uint32_t\|int32_t' "$f" 2>/dev/null; then
        if ! grep -q '#include <cstdint>' "$f" 2>/dev/null; then
          sed -i '1i #include <cstdint>' "$f"
        fi
      fi
      if grep -qE 'syscall|[^a-z]close\(' "$f" 2>/dev/null; then
        if ! grep -q '#include <unistd.h>' "$f" 2>/dev/null; then
          sed -i '1i #include <unistd.h>' "$f"
        fi
      fi
      if grep -q 'SYS_' "$f" 2>/dev/null; then
        if ! grep -q '#include <sys/syscall.h>' "$f" 2>/dev/null; then
          sed -i '1i #include <sys/syscall.h>' "$f"
        fi
      fi
    done

    # Fix protobuf/abseil linking
    sed -i '/find_package(Protobuf REQUIRED)/a find_package(absl REQUIRED)' CMakeLists.txt

    # Remove conda path that breaks builds
    sed -i '/link_directories.*CONDA_PREFIX/d' CMakeLists.txt
  '';

  meta = {
    description = "Vitis AI Runtime for AMD accelerators";
    homepage = "https://github.com/amd/vart";
    license = lib.licenses.asl20;
    platforms = [ "x86_64-linux" ];
    maintainers = with lib.maintainers; [ robcohen ];
  };
}
