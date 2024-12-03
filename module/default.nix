{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.fhs-compat;

  # Serialising the entire conf is smarter than checking against specific changes
  serialisedconf = pkgs.writeText "conf" (builtins.toJSON cfg);

  distro-image-mappings = {
    "debian"  = "docker.io/debian:latest";
    "ubuntu"  = "docker.io/ubuntu:latest";
    
    "alpine"  = "docker.io/alpine:latest";
    
    "arch"    = "docker.io/archlinux:latest";
    "manjaro" = "docker.io/manjarolinux/base:latest";
    
    "gentoo"  = "docker.io/gentoo/stage3:latest";
    
    "void"    = "docker.io/voidlinux/voidlinux:latest";
  };

  distro-init-commands-mappings = {
    "debian"  = "apt-get update && apt-get install -y ";
    "ubuntu"  = "apt-get update && apt-get install -y ";
    
    "alpine"  = "apk update && apk add ";
    
    "arch"    = "pacman -Syu --noconfirm --needed ";
    "manjaro" = "pacman -Syu --noconfirm --needed ";
    
    "gentoo"  = "emerge --sync && emerge ";
    
    "void"    = "xbps-install -S && xbps-install -yu xbps && xbps-install -Syu ";
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
    enable = mkOption {
      type = types.bool;
      default = false;
    };
    distro = mkOption {
      type = types.enum [ "debian" "ubuntu" "alpine" "arch" "manjaro" "gentoo" "void" ];
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
    stateDir = mkOption {
      type = types.str;
      default = "${cfg.mountPoint}/.state";
      description = ''
        A directory where the service itself stores data
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
    maxTimeDelta = mkOption {
      type = types.ints.unsigned;
      default = 60 * 60 * 24; # 1 day
      example = "60 * 35"; # 35 mins
      description = ''
        The maximum age any given FHS environment (in seconds).
        If the env is older than $maxTimeDelta (in seconds), it will be refreshed.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    systemd = {
      tmpfiles.rules = [
        "d  ${cfg.mountPoint} 755 root root - -"

        "L+ /lib   755 root root - ${cfg.mountPoint}/lib  "
        "L+ /lib32 755 root root - ${cfg.mountPoint}/lib32"
        "L+ /lib64 755 root root - ${cfg.mountPoint}/lib64"
        
        "L+ /sbin  755 root root - ${cfg.mountPoint}/sbin "
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
          config.virtualisation.podman.package
          util-linux
          diffutils
          inetutils
          mktemp
          rsync
        ];
        script = ''
          echo -n "Waiting for net."
          until ping -c1 github.com; do sleep 1; done
          echo "Ok."
          
          set -eu

          CONTAINERDIR=$(mktemp -d)
          mount -t tmpfs none -o size=${cfg.tmpfsSize},mode=755 $CONTAINERDIR

          handle_exit() {
              umount -l $CONTAINERDIR 2>/dev/null || true
              rm -rf $CONTAINERDIR
          }

          trap 'handle_exit' EXIT

          if ${if !cfg.persistent then "true" else "false"}; then
            rm -rf ${cfg.mountPoint}/*
            mount -t tmpfs none -o size=${cfg.tmpfsSize},mode=755 ${cfg.mountPoint}
          fi

          mkdir -pm 700 ${cfg.stateDir}

          if (! cmp -s ${cfg.stateDir}/serviceconf ${serialisedconf}) \
            || [ ! -e ${cfg.stateDir}/timestamp ] \
            || [ $(( $(date +%s) - $(cat ${cfg.stateDir}/timestamp) )) -ge ${builtins.toString cfg.maxTimeDelta} ]; then
            
            podman --root=$CONTAINERDIR pull ${distro-image-mappings.${cfg.distro}}
            
            podman --root=$CONTAINERDIR rm bootstrap -i
            podman --root=$CONTAINERDIR run --name bootstrap -v /nix:/nix:ro -t ${distro-image-mappings.${cfg.distro}} ${init-script}
            
            IMAGE_MOUNT=$(podman --root=$CONTAINERDIR mount bootstrap)

            echo "Preparing to replace old environment"
            rm -rf ${cfg.mountPoint}/* ${cfg.stateDir}/*
            
            echo "Saving service state"
            cp ${serialisedconf} ${cfg.stateDir}/serviceconf
            date +%s >${cfg.stateDir}/timestamp
            
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

          echo "${cfg.mountPoint} is ready"
        '';
        preStop = ''
          echo "Preparing cleanup"
          
          if ${if cfg.mountBinDirs then "true" else "false"}; then
              umount -O bind -l /usr /bin
          fi
          
          if ${if cfg.persistent then "true" else "false"}; then
            exit 0
          fi

          umount -t tmpfs -l ${cfg.mountPoint} || true
        '';
        serviceConfig."RemainAfterExit" = "true";
      };
    };

    assertions = [
      { assertion = config.virtualisation.podman.enable; message = "You need to enable podman."; }
    ];
  };
}