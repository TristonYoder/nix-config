{ config, pkgs, lib, ... }:

{
  imports = [
    ./modules/app-shortcuts.nix
  ];

  home.username = "carolineyoder";
  home.stateVersion = "25.05";

  programs.home-manager.enable = true;

  modules.appShortcuts.enable = true;
}
