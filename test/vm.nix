{ pkgs, ... }: {
  services.getty.autologinUser = "root";

  systemd.services.NetworkManager-wait-online.enable = false;

  services.fhs-compat = {
    mountPoint = "/very/custom/dir";
    distro = "arch";
    tmpfsSize = "4G";
    mountBinDirs = true;
    packages = [
      "neofetch"
      #"mesa" "lib32-mesa" "vulkan-radeon" "lib32-vulkan-radeon" "vulkan-icd-loader" "lib32-vulkan-icd-loader"
      #"giflib" "lib32-giflib" "libpng" "lib32-libpng" "libldap" "lib32-libldap" "gnutls" "lib32-gnutls" "mpg123" "lib32-mpg123" "openal" "lib32-openal" "v4l-utils" "lib32-v4l-utils" "libpulse" "lib32-libpulse" "libgpg-error" "lib32-libgpg-error" "alsa-plugins" "lib32-alsa-plugins" "alsa-lib" "lib32-alsa-lib" "libjpeg-turbo" "lib32-libjpeg-turbo" "sqlite" "lib32-sqlite" "libxcomposite" "lib32-libxcomposite" "libxinerama" "lib32-libgcrypt" "libgcrypt" "lib32-libxinerama" "ncurses" "lib32-ncurses" "ocl-icd" "lib32-ocl-icd" "libxslt" "lib32-libxslt" "libva" "lib32-libva gtk3" "lib32-gtk3" "gst-plugins-base-libs" "lib32-gst-plugins-base-libs"
      #"kdialog" "xdg-desktop-portal-kde"
    ];
    preInitCommand = ''
      cat << EOF >>/etc/pacman.conf
      [multilib]
      Include = /etc/pacman.d/mirrorlist
      EOF
    '';
    postInitCommand = ''
      pacman --version >/pacman-ver
    '';
    persistent = true;
  };

  virtualisation = {
    cores = 8;
    memorySize = 8096 * 2;
    diskSize = 10 * 1024;
  };

  nixos-shell.mounts = {
    mountHome = false;
    mountNixProfile = false;
  };

  environment.loginShellInit = ''
    trap 'poweroff' EXIT
  '';

  users.users."root".shell = pkgs.zsh;

  programs.zsh = {
    enable = true;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;
    ohMyZsh = {
      enable = true;
      theme = "flazz";
    };
  };

  networking.networkmanager.enable = true;

  system.stateVersion = "22.05";
}