{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.fhs-compat;

  pkglist = pkgs.writeText "pkgs" (builtins.toJSON cfg.packages);
  preCmd = pkgs.writeText "pkgs" cfg.preInitCommand;
  postCmd = pkgs.writeText "pkgs" cfg.postInitCommand;

  distro-image-mappings = {
    "arch" = "docker.io/archlinux:latest";
    "debian" = "docker.io/debian:latest";
    "void" = "docker.io/voidlinux/voidlinux:latest";
  };

  distro-init-commands-mappings = {
    "arch" = "pacman -Syu --noconfirm --needed ";
    "debian" = "apt update && apt install -y ";
    "void" = "xbps-install -S && xbps-install -yu xbps && xbps-install -Syu ";
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
      default = "5G";
      description = ''
        How big the tmpfs mounted on $mountPoint should be.
        This also affects the tmpfs size for temporary storage of the container.
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
    persistent = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        Try to persist the FHS environment across reboots.
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
        description = "Global FHS environment";
        after = [
          "network-online.target"
        ];
        wantedBy = [
          "multi-user.target"
        ];
        path = with pkgs; [
          util-linux
          diffutils
          inetutils
          mktemp
          podman
          rsync
        ];
        # TODO: Handle package changes
        script = ''
          echo -n "Waiting for net."
          until ping -c1 github.com; do sleep 1; done
          echo "Ok."
          
          set -eu

          CONTAINERDIR=$(mktemp -d)
          mount -t tmpfs none -o size=${cfg.tmpfsSize},mode=755 $CONTAINERDIR

          handle_exit() {
              umount -l $CONTAINERDIR || true
              rm -rf $CONTAINERDIR
          }

          trap 'handle_exit' EXIT

          if ${if !cfg.persistent then "true" else "false"}; then
            rm -rf ${cfg.mountPoint}/*
            mount -t tmpfs none -o size=${cfg.tmpfsSize},mode=755 ${cfg.mountPoint}
          fi

          if (! cmp -s ${cfg.mountPoint}/.pkglist ${pkglist}) \
            || (! cmp -s ${cfg.mountPoint}/.precmd ${preCmd}) \
            || (! cmp -s ${cfg.mountPoint}/.postcmd ${postCmd}); then
            rm -rf ${cfg.mountPoint}/*

            podman --root=$CONTAINERDIR pull ${distro-image-mappings.${cfg.distro}}
            
            podman --root=$CONTAINERDIR rm bootstrap -i
            podman --root=$CONTAINERDIR run --name bootstrap -v /nix:/nix:ro -t ${distro-image-mappings.${cfg.distro}} ${init-script}
            
            IMAGE_MOUNT=$(podman --root=$CONTAINERDIR mount bootstrap)
            
            echo "Saving package list"
            cp ${pkglist} ${cfg.mountPoint}/.pkglist
            cp ${preCmd} ${cfg.mountPoint}/.precmd
            cp ${postCmd} ${cfg.mountPoint}/.postcmd
            
            echo "Copying distro files to ${cfg.mountPoint}"
            rsync -a $IMAGE_MOUNT/* ${cfg.mountPoint}

            echo "Purging unwanted directories"
            rm -rf ${cfg.mountPoint}/{,usr/}lib/{systemd,tmpfiles.d,sysctl.d,udev,sysusers.d,pam.d}
            
            podman --root=$CONTAINERDIR umount bootstrap
            umount -l $CONTAINERDIR
            rm -rf $CONTAINERDIR
          else
            echo "Nothing changed, we can recycle this env."
          fi

          if ${if cfg.mountBinDirs then "true" else "false"}; then
              echo "Setting up bind-mounts"
              mount --bind ${cfg.mountPoint}/usr /usr
              mount --bind ${cfg.mountPoint}/bin /bin
          fi

          if [ ! -e ${cfg.mountPoint}/lib32 ]; then
            ln -s lib ${cfg.mountPoint}/lib32
          fi

          if ${if cfg.persistent then "true" else "false"}; then
            echo "${cfg.mountPoint} is ready"
            exit 0
          fi

          echo "Waiting for ${cfg.mountPoint} to be unmounted"
          while mountpoint -q ${cfg.mountPoint}; do true; done
          echo "${cfg.mountPoint} got unmounted. Good night."
        '';
        preStop = ''
          if ${if cfg.mountBinDirs then "true" else "false"}; then
              umount -O bind -l /usr /bin
          fi
          
          if ${if cfg.persistent then "true" else "false"}; then
            exit 0
          fi

          umount -t tmpfs -l ${cfg.mountPoint} || true
        '';
      };
    };

    virtualisation.podman.enable = true;
  };
}