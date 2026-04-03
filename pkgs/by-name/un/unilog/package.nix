{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  ninja,
  pkg-config,
  glog,
  boost,
}:

stdenv.mkDerivation rec {
  pname = "unilog";
  version = "3.5.0";

  src = fetchFromGitHub {
    owner = "amd";
    repo = "unilog";
    rev = "3abf8046d7ec8e651b8ec7ef19627a667ffaa741";
    hash = "sha256-TAsl/bCVwgVvbz3dQ9EKfBgZJArz4K2bae1hP/HuH3Q=";
  };

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
  ];

  buildInputs = [
    glog
    boost
  ];

  propagatedBuildInputs = [
    glog
    boost
  ];

  cmakeFlags = [
    (lib.cmakeBool "BUILD_TEST" false)
    (lib.cmakeBool "BUILD_PYTHON" false)
    (lib.cmakeBool "BUILD_SHARED_LIBS" true)
  ];

  postPatch = ''
    # Remove -Werror
    substituteInPlace cmake/VitisCommon.cmake \
      --replace-fail "-Werror" ""

    # Fix config.cmake.in to not fallback to pkg-config for glog
    substituteInPlace cmake/config.cmake.in \
      --replace-fail 'if(NOT glog_FOUND)
  message(STATUS "cannot find glogConfig.cmake fallback to pkg-config")
  find_package(PkgConfig)
  pkg_search_module(PKG_GLOG REQUIRED IMPORTED_TARGET GLOBAL libglog)
  add_library(glog::glog ALIAS PkgConfig::PKG_GLOG)
endif(NOT glog_FOUND)' 'if(NOT glog_FOUND)
  message(FATAL_ERROR "glog not found - ensure glog cmake config is available")
endif(NOT glog_FOUND)'

    # Fix glog API compatibility - LogMessageVoidify is not exposed in newer glog
    substituteInPlace include/UniLog/UniLog.hpp \
      --replace-fail '#include <glog/logging.h>' '#include <glog/logging.h>

// Compatibility shim for newer glog versions
#ifndef GOOGLE_GLOG_LOGMESSAGEVOIDIFY_DEFINED
namespace google {
class LogMessageVoidify {
 public:
  void operator&(std::ostream&) {}
};
}
#define GOOGLE_GLOG_LOGMESSAGEVOIDIFY_DEFINED
#endif'
  '';

  meta = {
    description = "Unified logging library for AMD Vitis AI";
    homepage = "https://github.com/amd/unilog";
    license = lib.licenses.asl20;
    platforms = [ "x86_64-linux" ];
    maintainers = with lib.maintainers; [ robcohen ];
  };
}
