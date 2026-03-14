{ inputs, pkgs, ... }:

{
  home.username = "hieunm";
  home.homeDirectory = "/home/hieunm";
  home.stateVersion = "24.11";

  imports = [
    inputs.niri.homeModules.niri
  ];

  programs.niri = {
    enable = true;
    settings = {
      prefer-no-csd = true;
    };
  };

  home.packages = [
    inputs.noctalia.packages.${pkgs.system}.default
  ];

  programs.home-manager.enable = true;
}