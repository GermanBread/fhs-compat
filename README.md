# Global FHS environment for NixOS

Possible thanks to OCI containers!

**Warning:** This module is not ready for usage. It bricks NixOS setups.

## Installation using flakes

`/etc/nixos/flake.nix`
```nix
{
  inputs = {
    # <snip>
    fhs-compat = {
      url = "github:GermanBread/fhs-compat";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # <snip>
  }

  outputs = { fhs-compat, ... }: {
    nixosConfigurations.<host> = nixpkgs.lib.nixosSystem {
      # <snip>
      modules = [
        # <snip>
        fhs-compat.nixosModules.fhs-compat
        # <snip>
        ./configuration.nix
      ]
      # <snip>
    }
  }
}
```

## Module definition

### services.fhs-compat.**distro**

```
default:
  "arch"

example:
  "debian"

description:
  Which distro to use for bootstrapping the FHS environment.
```

### services.fhs-compat.**tmpfsSize**

```
default:
  "2G"

description:
  How big the tmpfs mounted on $mountPoint should be.
  Sizes must have a valid suffix.
```

### services.fhs-compat.**mountPoint**

```
default:
  "/.fhs"

description:
  Where the FHS environment will be installed to.
```

### services.fhs-compat.**packages**

```
default:
  []

example:
  [ "neofetch" "sdl2" ]

description:
  Which packages to install. Package names vary from distro to distro.
```

### services.fhs-compat.**preInitCommand**

```
default:
  null

description:
  Which command to run on a fresh container.

  WARNING:
  Multiline strings have to be escaped properly, like so:
  foo && \
    bar

  Executable paths have to be absolute paths!
```

### services.fhs-compat.**postInitCommand**

```
default:
  null

example:
  "/bin/pacman -R neofetch sdl2";

description:
  Which command to run after packages have been installed.

  WARNING:
  Multiline strings have to be escaped properly, like so:
  foo && \
    bar

  Executable paths have to be absolute paths!