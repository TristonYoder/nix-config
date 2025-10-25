# Home Manager configuration for tyoder (macOS)

{ config, pkgs, lib, ... }:

{
  imports = [
    ./common.nix
    ./modules/homebrew.nix
    ./modules/mas.nix
    ./tristonyoder-darwin.nix
  ];
  
  # User and home directory
  home.username = "tyoder";
  home.homeDirectory = "/Users/tyoder";
  home.stateVersion = "25.05";
}

