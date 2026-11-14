{ config, pkgs, lib, ... }:

{
  imports = [
    ./modules/app-shortcuts.nix
  ];

  home.username = "juliayoder";
  home.stateVersion = "26.05";

  programs.home-manager.enable = true;

  modules.appShortcuts.enable = true;
}
