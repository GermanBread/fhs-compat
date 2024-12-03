{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.fhs-compat;

  distro-image-mappings = {
    "arch" = "docker.io/archlinux:latest";
    "debian" = "docker.io/debian:latest";
    "alpine" = "docker.io/alpine:latest";
  };

  distro-init-commands-mappings = {
    "arch" = "pacman -Syu --noconfirm";
    "debian" = "apt update && apt install -y";
    "alpine" = "apk add -u";
  };
in

{
  imports = [

  ];

  options.services.fhs-compat = {
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

  config = {
    systemd = {
      tmpfiles.rules = [
        "d  ${cfg.mountPoint} 755 root root - -"

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
        environment = {
          HOME = "${cfg.mountPoint}/.service-data";
        };
        script = ''
          mkdir -p $HOME

          podman pull ${distro-image-mappings.${cfg.distro}}
          
          podman run --name bootstrap ${distro-image-mappings.${cfg.distro}} ${distro-init-commands-mappings.${cfg.distro}} ${concatStringsSep " " cfg.packages}
          
          IMAGE_MOUNT=$(podman mount bootstrap)
          rsync -a $IMAGE_MOUNT/* ${cfg.mountPoint}
          podman umount bootstrap

          podman system reset -f
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