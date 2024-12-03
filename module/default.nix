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
    "arch" = "pacman -Syu --noconfirm --needed ";
    "debian" = "apt update && apt install -y";
    "void" = "xbps-install -S && xbps-install -yu xbps && xbps-install -Syu";
  };

  init-script = pkgs.writeShellScript "container-init" ''
    set -eu

    export PATH=/bin:/usr/bin:/sbin:/usr/sbin

    echo "Initialising container"
    ${if cfg.preInitCommand != null then cfg.preInitCommand else "true"}
    ${distro-init-commands-mappings.${cfg.distro}} ${concatStringsSep " " cfg.packages}
    ${if cfg.postInitCommand != null then cfg.postInitCommand else "true"}
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
    mountBinDirs = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        Whether or not to put a bind mount over /bin and /usr.
        Both will redirect to their counterparts in $mountPoint.

        This option does not affect /sbin.
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
        Which command(s) to run on a fresh container.
      '';
    };
    postInitCommand = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "pacman -R neofetch sdl2";
      description = ''
        Which command(s) to run after packages have been installed.
      '';
    };
  };

  config = {
    systemd = {
      tmpfiles.rules = [
        "d  ${cfg.mountPoint} 755 root root - -                      "

        "L+ /lib              755 root root - ${cfg.mountPoint}/lib  "
        "L+ /lib32            755 root root - ${cfg.mountPoint}/lib32"
        "L+ /lib64            755 root root - ${cfg.mountPoint}/lib64"
        
        "L+ /sbin             755 root root - ${cfg.mountPoint}/sbin "
      ];

      services."manage-global-fhs-env" = {
        after = [
          "network-online.target"
        ];
        wantedBy = [
          "multi-user.target"
        ];
        path = with pkgs; [
          util-linux
          podman
          rsync
        ];
        script = ''
          set -eu

          handle_exit() {
              podman rm bootstrap -i
          }

          trap 'handle_exit' EXIT

          podman pull ${distro-image-mappings.${cfg.distro}}
          
          podman rm bootstrap -i
          podman run --name bootstrap -v /nix:/nix:ro -t ${distro-image-mappings.${cfg.distro}} ${init-script}
          
          IMAGE_MOUNT=$(podman mount bootstrap)
          
          mount -t tmpfs none -o size=${cfg.tmpfsSize},mode=755 ${cfg.mountPoint}
          
          echo "Copying distro files to ${cfg.mountPoint}"
          rsync -a $IMAGE_MOUNT/* ${cfg.mountPoint}

          echo "Purging unwanted directories"
          rm -rf ${cfg.mountPoint}/{,usr/}lib/{systemd,tmpfiles.d,sysctl.d,udev,sysusers.d,pam.d}
          
          podman umount bootstrap
          podman rm bootstrap -i

          if ${if cfg.mountBinDirs then "true" else "false"}; then
              echo "Setting up bind-mounts"
              mount --bind ${cfg.mountPoint}/usr /usr
              mount --bind ${cfg.mountPoint}/bin /bin
          fi

          echo "Waiting for ${cfg.mountPoint} to be unmounted"
          while mountpoint -q ${cfg.mountPoint}; do true; done
          echo "${cfg.mountPoint} got unmounted. Good night."
        '';
        preStop = ''
          if ${if cfg.mountBinDirs then "true" else "false"}; then
              umount -O bind -l /usr /bin
          fi
          umount -t tmpfs -l ${cfg.mountPoint}
        '';
      };
    };

    virtualisation.podman.enable = true;
  };
}