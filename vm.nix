{ pkgs, ... }: {
  imports = [
    ./.
  ];

  services.getty.autologinUser = "root";

  services.fhs-compat = {
    mountPoint = "/fhs";
    distro = "arch";
    packages = [ "neofetch" ];
  };

  virtualisation = {
    cores = 8;
    memorySize = 8096;
  };

  system.stateVersion = "22.05";
}