{
  description = "ArduPilot";

  inputs = {
    nixpkgs.url = "github:lopsided98/nixpkgs/python-cross-musl";
    flake-utils.url = "github:numtide/flake-utils";
    arduplane-stable = {
      type = "git";
      url = "https://github.com/ArduPilot/ardupilot";
      ref = "refs/tags/ArduPlane-stable";
      flake = false;
      submodules = true;
    };
    arducopter-beta = {
      type = "git";
      url = "https://github.com/ArduPilot/ardupilot";
      ref = "refs/tags/ArduCopter-beta";
      flake = false;
      submodules = true;
    };
    arducopter-bebop = {
      type = "git";
      url = "https://github.com/lopsided98/ardupilot";
      ref = "refs/heads/parrot-bebop";
      flake = false;
      submodules = true;
    };
  };

  outputs = inputs: let
    systems = [ "x86_64-linux" ];
  in
    inputs.flake-utils.lib.eachSystem systems (system: let
      pkgs = inputs.nixpkgs.legacyPackages.${system};
      lib = inputs.nixpkgs.lib;

      fake-git = pkgs.callPackage ./fake-git.nix { };
      
      ardupilot = {
        src,
        firmware,
        board, ...
      }@args: pkgs.callPackage ./. (args // {
        git = fake-git src;
      });
      
      ardupilotShell = {
        firmware,
        board, ...
      }@args: pkgs.callPackage ./. (args // {
        src = null;
        dev = true;
      });
      
      builds = {
        bebop-copter = {
          src = inputs.arducopter-bebop;
          firmware = "copter";
          board = "bebop";
        };
        matekh743-plane = {
          src = inputs.arduplane-stable;
          firmware = "plane";
          board = "MatekH743";
        };
        omnibusf4pro-plane = {
          src = inputs.arduplane-stable;
          firmware = "plane";
          board = "omnibusf4pro";
        };
      };
    in {
      packages = lib.mapAttrs (_: args: ardupilot args) builds;
      devShells = lib.mapAttrs (_: args: ardupilotShell args) builds;
      hydraJobs = inputs.self.packages.${system};
    });
}
