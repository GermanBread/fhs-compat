{
  description = "Global FHS environment for your daily computing needs.";

  outputs = { self, nixpkgs }: let
    pkgs = nixpkgs.legacyPackages."x86_64-linux";
  in {
    nixosModules = rec {
      fhs-compat = import ./module;
      default = fhs-compat;
    };

    devShells.x86_64-linux.default = pkgs.mkShell {
      buildInputs = with pkgs; [
        nixos-shell
      ];
    };
  };
}
