# Home Manager configuration for tristonyoder (cross-platform)
# macOS-specific modules are imported separately via flake.nix to avoid platform issues

{ config, pkgs, lib, ... }:

{
  imports = [
    ./common.nix
  ];
  
  # User (platform-specific)
  home.username = "tristonyoder";
  
  # Home directory set by flake.nix (platform-specific)
  # - NixOS: /home/tristonyoder
  # - macOS: /Users/tristonyoder
  
  home.stateVersion = "25.05";
}

