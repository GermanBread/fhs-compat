{
  description = "Global FHS environment for your daily computing needs.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }: let
    pkgs = nixpkgs.legacyPackages."x86_64-linux";
  in {
    nixosModules = rec {
      global-fhs-env = import ./module;
      default = global-fhs-env;
    };

    devShells.x86_64-linux.default = pkgs.mkShell {
      buildInputs = with pkgs; [
        nixos-shell
      ];
    };
  };
}
