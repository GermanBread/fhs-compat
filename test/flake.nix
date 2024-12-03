{
  inputs = {
    nixpkgs.url = github:NixOS/nixpkgs/nixos-22.11;
    nixos-shell.url = "github:Mic92/nixos-shell";
    fhs.url = "./..";
  };

  outputs = { self, nixpkgs, fhs, nixos-shell }: let
    system = "x86_64-linux";
    import-config = {
      inherit system;
      config.allowUnfree = true;
    };
  in {
    nixosConfigurations.vm = nixpkgs.lib.makeOverridable nixpkgs.lib.nixosSystem rec {
      pkgs = import nixpkgs {
        inherit system;
      };
      inherit system;
      modules = [
        nixos-shell.nixosModules.nixos-shell

        fhs.nixosModules.default
        ./vm.nix
      ];
    };
  };
}
