{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.fhs-compat;

  distro-image-mappings = {
    "arch" = "docker.io/archlinux:latest";
    "debian" = "docker.io/debian:latest";
    "void" = "docker.io/voidlinux/voidlinux:latest";
  };

  distro-init-commands-mappings = {
    "arch" = "/bin/pacman -Syu --noconfirm";
    "debian" = "/bin/apt update && /bin/apt install -y";
    "void" = "/bin/xbps-install -S && /bin/xbps-install -yu xbps && /bin/xbps-install -Syu";
  };

  init-script = pkgs.writeShellScript "container-init" ''
    set -eu

    echo "Initialising container"
    ${if cfg.preInitCommand != null then cfg.preInitCommand else "true"}
    ${distro-init-commands-mappings.${cfg.distro}} ${concatStringsSep " " cfg.packages}
    if ${if cfg.postInitCommand != null then "true" else "false"}; then
      echo "Running extra commands"
      ${if cfg.postInitCommand != null then cfg.postInitCommand else "true"}
    fi
  '';
in

{
  options.services.fhs-compat = {
    distro = mkOption {
      type = types.str;
      default = "arch";
      example = "debian";
      description = ''
        Which distro to use for bootstrapping the FHS environment.
      '';
    };
    tmpfsSize = mkOption {
      type = types.str;
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
    preInitCommand = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        Which command to run on a fresh container.
        
        WARNING:
        Multiline strings have to be escaped properly, like so:
        foo && \
          bar

        Executable paths have to be absolute paths!
      '';
    };
    postInitCommand = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "/bin/pacman -R neofetch sdl2";
      description = ''
        Which command to run after packages have been installed.
        
        WARNING:
        Multiline strings have to be escaped properly, like so:
        foo && \
          bar

        Executable paths have to be absolute paths!
      '';
    };
  };

  config = {
    systemd = {
      tmpfiles.rules = [
        "d  ${cfg.mountPoint} 755 root root - -                    "

        "L+ /usr              755 root root - ${cfg.mountPoint}/usr"
        "L+ /lib              755 root root - usr/lib              "
        "L+ /lib32            755 root root - usr/lib32            "
        "L+ /lib64            755 root root - usr/lib64            "
        "L+ /bin              755 root root - usr/bin              "
        "L+ /sbin             755 root root - usr/sbin             "
      ];

      mounts = [
        {
          what = "none";
          where = cfg.mountPoint;
          type = "tmpfs";
          requires = [
            "systemd-tmpfiles-setup.service"
          ];
          wantedBy = [
            "basic.target"
          ];
          options = "size=${cfg.tmpfsSize},mode=755";
          description = "tmpfs mount for FHS environment";
        }
      ];

      services."create-fhs-environment" = {
        wantedBy = [
          "multi-user.target"
        ];
        after = [
          "network-online.target"
        ];
        path = with pkgs; [
          podman
          rsync
        ];
        script = ''
          set -eu
          trap 'podman rm bootstrap -i' EXIT

          podman pull ${distro-image-mappings.${cfg.distro}}
          
          podman run --name bootstrap -v /nix:/nix ${distro-image-mappings.${cfg.distro}} ${init-script}
          
          IMAGE_MOUNT=$(podman mount bootstrap)
          rsync -a $IMAGE_MOUNT/* ${cfg.mountPoint}
          podman umount bootstrap
        '';
        unitConfig = {
          ConditionPathIsMountPoint = cfg.mountPoint;
        };
      };
    };

    virtualisation.podman.enable = true;

    # stolen from https://github.com/balsoft/nixos-fhs-compat/blob/master/modules/fhs.nix
    system.activationScripts = {
      binsh = (mkForce "");
      usrbinenv = (mkForce "");
    };
  };
}