# Home Manager configuration for tyoder (macOS)

{ config, pkgs, lib, ... }:

{
  imports = [
    ./common.nix
    ./modules/homebrew.nix
    ./modules/mas.nix
    ./modules/apple-mail-mcp.nix
    ./tristonyoder-darwin.nix
  ];

  # User and home directory
  home.username = "tyoder";
  home.homeDirectory = "/Users/tyoder";
  home.stateVersion = "25.05";

  # Apple Mail MCP server for the Claude desktop app (work MacBook only).
  modules.mcp.appleMail.enable = true;
}

