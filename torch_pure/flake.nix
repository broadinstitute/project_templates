{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    nixpkgs_master.url = "github:NixOS/nixpkgs/master";
    systems.url = "github:nix-systems/default";
    flake-utils.url = "github:numtide/flake-utils";
    flake-utils.inputs.systems.follows = "systems";
  };

  outputs = { self, nixpkgs, flake-utils, systems, ... } @ inputs:
      flake-utils.lib.eachDefaultSystem (system:
        let
            pkgs = import nixpkgs {
              system = system;
              config.allowUnfree = true;
              config.cudaSupport = true;
            };

            mpkgs = import inputs.nixpkgs_master {
              system = system;
              config.allowUnfree = true;
              config.cudaSupport = true;
            };
 
            libList = [
                # Add needed packages here
                pkgs.stdenv.cc.cc
                pkgs.libGL
                pkgs.glib
              ] ++ pkgs.lib.optionals pkgs.stdenv.isLinux (with mpkgs.cudaPackages; [
                libcublas
                libcurand
                pkgs.cudaPackages.cudnn
                libcufft
                cuda_cudart

                # This is required for most app that uses graphics api
                pkgs.linuxPackages.nvidia_x11
              ]);

          in
          with pkgs;
        {
          devShells = {
              default = let 
                python_with_pkgs = (pkgs.python311.withPackages(pp: [
                  pp.torch
                  pp.torchvision
                  pp.scikit-image
                ]));
              in mkShell {
                    NIX_LD = runCommand "ld.so" {} ''
                        ln -s "$(cat '${pkgs.stdenv.cc}/nix-support/dynamic-linker')" $out
                      '';
                    NIX_LD_LIBRARY_PATH = lib.makeLibraryPath libList;
                    packages = [
                      python_with_pkgs
                      python311Packages.venvShellHook
                      mpkgs.python311Packages.cupy
                      mpkgs.python311Packages.ray
                      uv
                    ]
                    ++ libList; 
                    venvDir = "./.venv";
                    postVenvCreation = ''
                        unset SOURCE_DATE_EPOCH
                      '';
                    postShellHook = ''
                        unset SOURCE_DATE_EPOCH
                      '';
                    shellHook = ''
                        export LD_LIBRARY_PATH=$NIX_LD_LIBRARY_PATH:$LD_LIBRARY_PATH
                        export PYTHON_KEYRING_BACKEND=keyring.backends.fail.Keyring
                        runHook venvShellHook
                        uv pip sync requirements.txt
                        export PYTHONPATH=${python_with_pkgs}/${python_with_pkgs.sitePackages}:$PYTHONPATH
                    '';
                  };
              };
        }
      );
}
