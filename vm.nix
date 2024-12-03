{ pkgs, ... }: {
  imports = [
    ./.
  ];

  services.getty.autologinUser = "root";

  services.fhs-compat = {
    mountPoint = "/fhs";
    distro = "arch";
    packages = [
      "neofetch"
      "vulkan-radeon" "lib32-vulkan-radeon" "mesa" "lib32-mesa"
      "pipewire" "pipewire-pulse" "pipewire-alsa"
      "lib32-pipewire"
    ];
    preInitCommand = ''
    cat << EOF >>/etc/pacman.conf
    [multilib]
    Include = /etc/pacman.d/mirrorlist
    EOF
    '';
  };

  virtualisation = {
    cores = 8;
    memorySize = 8096;
    diskSize = 10 * 1024;
  };

  system.stateVersion = "22.05";
}