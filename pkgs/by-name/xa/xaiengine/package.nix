{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  ninja,
}:

stdenv.mkDerivation rec {
  pname = "xaiengine";
  version = "3.8";

  src = fetchFromGitHub {
    owner = "Xilinx";
    repo = "aie-rt";
    rev = "4a012d7932155217d2c9368a3588a3c41d2b9edb";
    hash = "sha256-nI8RZod53HYfo1GEJYu0pOOWUHrG3+jGh2etmDl//eY=";
  };

  sourceRoot = "${src.name}/driver";

  nativeBuildInputs = [
    cmake
    ninja
  ];

  cmakeFlags = [
    (lib.cmakeBool "WITH_TESTS" false)
    (lib.cmakeBool "BUILD_SHARED_LIBS" true)
  ];

  postPatch = ''
    substituteInPlace src/CMakeLists.txt \
      --replace-quiet '-Werror' "" || true
  '';

  meta = {
    description = "AMD AIE Runtime driver library";
    homepage = "https://github.com/Xilinx/aie-rt";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    maintainers = with lib.maintainers; [ robcohen ];
  };
}
