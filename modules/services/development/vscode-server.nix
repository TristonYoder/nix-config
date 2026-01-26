{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.development.vscode-server;
in
{
  options.modules.services.development.vscode-server = {
    enable = mkEnableOption "VSCode Server for remote development";
  };

  config = mkIf cfg.enable {
    # Disabled in favor of code-server
    # services.vscode-server.enable = true;
  };
}

