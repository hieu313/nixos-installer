{ config, pkgs, inputs, ... }:

{
  networking.hostName = "nixos-vm";

  boot.loader.grub = {
    enable = true;
    device = "/dev/sda";
  };

  time.timeZone = "Asia/Ho_Chi_Minh";

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    substituters = [
      "https://cache.nixos.org"
      "https://niri.cachix.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "niri.cachix.org-1:Wv0OmO7PsuocRKzfDoJ3mulSl7Z6oezYhGhR+3W2964="
    ];
  };

  programs.niri.enable = true;
  hardware.graphics.enable = true;

  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --cmd niri";
      user = "greeter";
    };
  };

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
    wireplumber.enable = true;
  };

  users.users.hieunm = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "video" "audio" ];
    initialPassword = "changeme";
  };

  networking.networkmanager.enable = true;

  environment.systemPackages = with pkgs; [
    git curl vim htop kitty
  ];

  services.openssh.enable = true;
  system.stateVersion = "24.11";
}