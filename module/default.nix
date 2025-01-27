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

  linkPaths = [
    "/lib"
    "/lib32"
    "/lib64"
    "/sbin"
    "/opt"
  ];
  bindPaths = [
    "/usr"
    "/bin"
  ];
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
          podman
          mktemp
          rsync
        ];
        script = ''
          echo -n "Waiting for net."
          until ping -c1 github.com; do sleep 1; done
          echo "Ok."

          set -eu

          mkdir -pm 755 ${cfg.mountPoint}
          mkdir -p ${cfg.mountPoint}/{usr,bin}

          if ${if !cfg.persistent then "true" else "false"}; then
            rm -rf ${cfg.stateDir} ${cfg.mountPoint}/*
            mount -t tmpfs none -o size=${cfg.tmpfsSize},mode=755 ${cfg.mountPoint}
          fi

          echo "Setting up symlinks"
          rm -rf ${cfg.stateDir}/not-linked
          mkdir -pm 755 ${cfg.stateDir}/not-linked
          ${builtins.toString (builtins.map (path: ''
          if ([ ! -e ${path} ] && ! mountpoint -q --nofollow ${path}) || ([ -L ${path} ] && [[ "$(readlink ${path})" = "${cfg.mountPoint}"* ]]); then
            ln -svfT ${cfg.mountPoint}${path} ${path}
          else
            echo "Did not link ${path}"
            touch ${cfg.stateDir}/not-linked${path}
          fi
          '') linkPaths)}

          ${if cfg.mountBinDirs then ''
          echo "Setting up bind-mounts"
          ${builtins.toString (builtins.map (path: ''
          mkdir -p ${cfg.mountPoint}${path}
          umount -l -O bind ${path} || true
          mount --bind ${cfg.mountPoint}${path} ${path}

          # Mount FSTAB
          mount -a
          '') bindPaths)}
          '' else ''''}

          if ${if cfg.persistent then "false" else "true"} \
            || (! cmp -s ${cfg.stateDir}/serviceconf ${serialisedconf}) \
            || [ ! -e ${cfg.stateDir}/timestamp ] \
            || [ $(( $(date +%s) - $(cat ${cfg.stateDir}/timestamp) )) -ge ${builtins.toString cfg.maxTimeDelta} ]; then

            CONTAINERDIR=$(mktemp -d)
            mount -t tmpfs none -o size=${cfg.tmpfsSize},mode=755 $CONTAINERDIR

            podman --root=$CONTAINERDIR pull ${distro-image-mappings.${cfg.distro}}

            podman --root=$CONTAINERDIR rm bootstrap -i
            podman --root=$CONTAINERDIR run --name bootstrap -v /nix:/nix:ro -t ${distro-image-mappings.${cfg.distro}} ${init-script}

            IMAGE_MOUNT=$(podman --root=$CONTAINERDIR mount bootstrap)

            echo "Purging unwanted directories"
            rm -rf $IMAGE_MOUNT/{,usr/}lib/{systemd,tmpfiles.d,sysctl.d,udev,sysusers.d,pam.d}

            echo "Cloning tree"
            rsync -a --delete $IMAGE_MOUNT/ ${cfg.mountPoint}

            ${if cfg.mountBinDirs then ''
            echo "Remounting bind-mounts"
            ${builtins.toString (builtins.map (path: ''
            mkdir -p ${cfg.mountPoint}${path}
            umount -R -l -O bind ${path} || true
            mount --bind ${cfg.mountPoint}${path} ${path}
            '') bindPaths)}
            '' else ''''}

            podman --root=$CONTAINERDIR umount bootstrap
            umount -l $CONTAINERDIR
            rm -rf $CONTAINERDIR

            echo "Saving service state"
            mkdir -pm 700 ${cfg.stateDir}
            cp ${serialisedconf} ${cfg.stateDir}/serviceconf
            date +%s >${cfg.stateDir}/timestamp
          else
            echo "Nothing changed, we can recycle this env."
          fi

          if [ ! -e ${cfg.mountPoint}/lib32 ]; then
            ln -s lib ${cfg.mountPoint}/lib32
          fi

          echo "${cfg.mountPoint} is ready"
        '';
        preStop = ''
          ${if cfg.persistent then '''' else ''
          umount -t tmpfs -l ${cfg.mountPoint} || true
          ''}

          ${builtins.toString (builtins.map (path: ''
          if [ ! -e ${cfg.stateDir}/not-linked${path} ]; then
            rm -vf ${path}
          else
            echo "Not unlinking ${path}"
          fi
          '') linkPaths)}
          
          ${if cfg.mountBinDirs then ''
          ${builtins.toString (builtins.map (path: ''
          umount -l -O bind ${path} || true
          '') bindPaths)}
          '' else ''''}
        '';
        serviceConfig."RemainAfterExit" = "true";
      };
    };

    assertions = [
      { assertion = config.virtualisation.podman.enable; message = "You need to enable podman."; }
    ];
  };
}