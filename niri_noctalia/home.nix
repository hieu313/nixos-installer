{ inputs, pkgs, ... }:

{
  home.username = "hieunm";
  home.homeDirectory = "/home/hieunm";
  home.stateVersion = "24.11";

  home.packages = [
    inputs.noctalia.packages.${pkgs.system}.default
  ];

  programs.home-manager.enable = true;
}