{ pkgs
, pkgsStatic
, pkgsCross
, callPackage

, which
, gawk
, git
, python3
, gcc-arm-embedded

, glibcLocales
, astyle
, mavproxy
, procps

, src ? null
, dev ? false
, firmware
, board
}:
assert !dev -> src != null;
let
  platform = {
    "bebop" = "linux";
    "sitl" = "native";
  }.${board} or "stm32";

  isStatic = platform == "linux";

  pkgsHost = if platform == "linux"
    then {
        "bebop" = pkgsCross.armv7l-hf-multiplatform;
      }.${board}.pkgsStatic
    else pkgs;
  pkgsBuild = if true
    then pkgs.pkgsStatic
    else pkgsHost.buildPackages;
in pkgsHost.callPackage ({
  lib
, stdenv
, buildPackages

, pkg-config
, gdb

, libiio
}: stdenv.mkDerivation {
  pname = "ardupilot-${firmware}-${board}";
  version = if src != null then src.shortRev else "";

  inherit src;

  nativeBuildInputs = [ pkg-config which gawk git pkgsBuild.stdenv.cc ] ++
    (with python3.pkgs; [ future pyserial empy pexpect setuptools ]) ++
    lib.optional (platform == "stm32") gcc-arm-embedded ++
    lib.optionals dev [ glibcLocales astyle mavproxy procps gdb ];

  buildInputs = [
    ((libiio.override {
      avahiSupport = false;
      libxml2 = null;
      libusb1 = null;
    }).overrideAttrs ({
      cmakeFlags ? [], ...
    }: {
      cmakeFlags = cmakeFlags ++ [
        "-DWITH_NETWORK_BACKEND=OFF"
        "-DWITH_USB_BACKEND=OFF"
        "-DWITH_XML_BACKEND=OFF"
      ];
    }))
  ];

  # HOST_GDB = pkgsHost.gdb.override { enableDebuginfod = false; };

  postPatch = ''
    patchShebangs waf
    substituteInPlace libraries/AP_Scripting/wscript \
      --replace '"gcc"' '"${pkgsBuild.stdenv.hostPlatform.config}-gcc"'
  '';

  # Disable optimizations, which cause -Werror failures with the Lua bindings
  # generator.
  hardeningDisable = [ "fortify" ];

  # Fully strip to reduce binary size
  stripAllList = [ "bin" ];

  # Prevent waf from using the host compiler
  preConfigure = ''
    export PKGCONFIG="$PKG_CONFIG"
  '' + lib.optionalString (platform != "linux") ''
    unset CXX CC OBJCOPY SIZE
  '';

  wafConfigureFlags = [ "--board" board ] ++
    lib.optional isStatic "--static";

  configurePhase = ''
    runHook preConfigure
    ./waf configure $wafConfigureFlags
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    ./waf '${firmware}'
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    mv 'build/${board}/bin' "$out/bin"
    runHook postInstall
  '';

  shellHook = ''
    runHook preConfigure
  '';
}) { }
