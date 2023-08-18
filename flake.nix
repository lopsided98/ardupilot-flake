{
  description = "ArduPilot";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    arduplane-stable = {
      type = "git";
      url = "https://github.com/ArduPilot/ardupilot";
      ref = "refs/tags/ArduPlane-stable";
      flake = false;
      submodules = true;
    };
    arduplane-beta = {
      type = "git";
      url = "https://github.com/ArduPilot/ardupilot";
      ref = "refs/tags/ArduPlane-beta";
      flake = false;
      submodules = true;
    };
    arducopter-stable = {
      type = "git";
      url = "https://github.com/ArduPilot/ardupilot";
      ref = "refs/tags/ArduCopter-stable";
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
    arduplane-masters-thesis = {
      type = "git";
      url = "https://github.com/lopsided98/ardupilot";
      ref = "refs/heads/masters-thesis";
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
        copter-beta-bebop = {
          src = inputs.arducopter-bebop;
          firmware = "copter";
          board = "bebop";
        };
        copter-stable-cubesolo = {
          src = inputs.arducopter-stable;
          firmware = "copter";
          board = "CubeSolo";
        };
        copter-beta-cubesolo = {
          src = inputs.arducopter-beta;
          firmware = "copter";
          board = "CubeSolo";
        };
        # Fails to build
        #plane-stable-matekh743 = {
        #  src = inputs.arduplane-stable;
        #  firmware = "plane";
        #  board = "MatekH743";
        #};
        plane-beta-matekh743 = {
          src = inputs.arduplane-beta;
          firmware = "plane";
          board = "MatekH743";
        };
        plane-masters-thesis-matekh743 = {
          src = inputs.arduplane-masters-thesis;
          firmware = "plane";
          board = "MatekH743";
        };
        plane-stable-omnibusf4pro = {
          src = inputs.arduplane-stable;
          firmware = "plane";
          board = "omnibusf4pro";
        };
        plane-beta-omnibusf4pro = {
          src = inputs.arduplane-beta;
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
