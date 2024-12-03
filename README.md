# Global FHS environment for NixOS

### Possible thanks to OCI containers!

Module definition:
```nix
services.fhs-compat = {
  distro = mkOption {
    type = types.str;
    default = "debian";
    example = "arch";
    description = ''
      Which distro to use for bootstrapping the FHS environment.
    '';
  };
  tmpfsSize = mkOption {
    default = "2G";
    description = ''
      How big the tmpfs mounted on $mountPoint should be.
      Sizes must have a valid suffix.
    '';
  };
  mountPoint = mkOption {
    type = types.str;
    default = "/.fhs";
    description = ''
      Where the FHS environment will be installed to.
    '';
  };
  packages = mkOption {
    type = types.listOf types.str;
    default = [];
    example = [ "neofetch" "sdl2" ];
    description = ''
      Which packages to install. Package names vary from distro to distro.
    '';
  };
};
```