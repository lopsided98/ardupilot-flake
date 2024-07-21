{ nixpkgs
, lib
, stdenv
, git

, src ? null
, dev ? false
, firmware
, board
}:
assert !dev -> src != null;
let
  hostPlatform = {
    "bebop" = {
      config = "armv7l-unknown-linux-musleabihf";
      isStatic = true;
      gcc = {
        # See: https://github.com/gcc-mirror/gcc/blob/36eec7995b4d53083c3ee7824bd765b5eba8b1a1/gcc/config/arm/arm-cpus.in#L1167
        arch = "armv7-a+mp+sec+neon-fp16";
        tune = "cortex-a9";
      };
    };
    "sitl" = stdenv.hostPlatform;
  }.${board} or {
    config = "arm-none-eabi";
    libc = "newlib-nano";
    gcc = {
      arch = "armv7e-m+fp";
      float-abi = "hard";
    };
  };

  empyOverlay = final: prev: {
    pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
      (pyFinal: pyPrev: {
        # ArduPilot is incompatible with Empy 4
        # em.ParseError: unknown markup sequence: `@)`; the `@)` markup has been removed, just use `)` instead
        empy_3 = pyPrev.empy.overrideAttrs ({
          pname, ...
        }: rec {
          version = "3.3.4";
          src = pyFinal.fetchPypi {
            inherit pname version;
            hash = "sha256-c6xJeFtgFHnfTqGKfHm8EwSop8NMArlHLPEgauiPAbM=";
          };
        });
      })
    ];
  };

  # Optimize for size on bare metal platforms. This makes the build small
  # enough to fit ArduPilot on 1 MiB processors.
  optimizeSizeOverlay = final: prev: lib.optionalAttrs prev.stdenv.hostPlatform.isNone {
    stdenv = lib.pipe prev.stdenv [
      # Optimize newlib
      (prev.withCFlags [ "-Os" ])
      # Optimize libstdc++
      (stdenv: prev.overrideCC stdenv (prev.buildPackages.wrapCCWith {
        cc = prev.buildPackages.gcc-unwrapped.overrideAttrs ({ env ? {}, ... }: {
          env = env // {
            EXTRA_FLAGS_FOR_TARGET = (env.EXTRA_FLAGS_FOR_TARGET or "") + " -Os";
          };
        });
      }))
    ];
  };

  # musl tries to call time64 ioctls and falls back to the old versions if they
  # aren't available. The Bebop kernel is too old to support time64, and it
  # also has a bug where attempting to call the time64 ioctl just hangs,
  # preventing the fallback logic from working. This overlay patches musl to
  # not attempt to call the v4l2 time64 ioctls.
  bebopMuslIoctlHackOverlay = final: prev: {
    musl = prev.musl.overrideAttrs ({ patches ? [], buildInputs ? [], ... }: {
      # musl is compiled with -nostdinc, but this forces the headers to be on
      # the include path of the compiler wrapper.
      buildInputs = buildInputs ++ [ final.linuxHeaders ];
      patches = patches ++ [ ./0001-Don-t-attempt-to-call-v4l2-time64-ioctls.patch ];
    });
  };

  pkgsHost = nixpkgs {
    localSystem = stdenv.hostPlatform;
    crossSystem = hostPlatform;
    overlays = [ empyOverlay optimizeSizeOverlay ] ++
      lib.optional (board == "bebop") bebopMuslIoctlHackOverlay;
  };
in pkgsHost.callPackage ({
  lib
, stdenv
, pkgsBuildBuild
, buildPackages

, pkg-config
, which
, gawk
, gcc-arm-embedded

, glibcLocales
, astyle
, mavproxy
, procps
, gdbHostCpuOnly

, libiio
}: stdenv.mkDerivation {
  pname = "ardupilot-${firmware}-${board}";
  version = if src != null then src.shortRev else "";

  inherit src;

  depsBuildBuild = [ pkgsBuildBuild.stdenv.cc ] ++
    lib.optionals dev [ glibcLocales astyle procps /* mavproxy */ ];
  nativeBuildInputs = [ pkg-config which gawk git ] ++
    # waf depends on imp, which was removed in 3.12
    (with buildPackages.python311.pkgs; [ future pyserial empy_3 pexpect setuptools ]) ++
    lib.optionals dev [ gdbHostCpuOnly ];

  buildInputs = lib.optional (board == "bebop") ((libiio.override {
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
  }));

  # env.HOST_GDB = pkgsHost.gdb.override { enableDebuginfod = false; };

  postPatch = ''
    patchShebangs waf
  '';

  separateDebugInfo = true;

  # No point in stripping bare metal platforms because we don't actually
  # run the ELF file.
  dontStrip = stdenv.hostPlatform.isNone;
  # Fully strip to reduce binary size
  stripAllList = [ "bin" ];

  preConfigure = ''
    export PKGCONFIG="$PKG_CONFIG"
  '';

  wafConfigureFlags = [ "--board" board ] ++
    lib.optional stdenv.hostPlatform.isStatic "--static";

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
