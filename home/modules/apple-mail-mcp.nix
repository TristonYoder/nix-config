# Apple Mail MCP server (patrickfreyer/apple-mail-mcp)
#
# Registers the `mcp-apple-mail` server with the Claude desktop app so Claude
# can read/search/send Apple Mail. The server is fetched and run on demand by
# `uvx` (from the `uv` package) — no persistent install.
#
# Home Manager module. Import + enable it in a user's home config, e.g.:
#   imports = [ ./modules/apple-mail-mcp.nix ];
#   modules.mcp.appleMail.enable = true;
#
# NOTE: On first use, macOS prompts to allow Claude to control Mail.app
# (System Settings > Privacy & Security > Automation). This grant is per-user
# and cannot be declared in nix — approve it once when Claude first runs a tool.

{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.mcp.appleMail;
in
{
  options.modules.mcp.appleMail = {
    enable = mkEnableOption "Apple Mail MCP server for the Claude desktop app";

    readOnly = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Run the server in read-only mode. Claude can read and search mail but
        cannot send, move, or delete messages.
      '';
    };

    package = mkOption {
      type = types.package;
      default = pkgs.uv;
      defaultText = literalExpression "pkgs.uv";
      description = "The uv package providing `uvx`, used to fetch and run mcp-apple-mail.";
    };

    configPath = mkOption {
      type = types.str;
      default = "Library/Application Support/Claude/claude_desktop_config.json";
      description = ''
        Path (relative to the user's home) of the Claude desktop app's MCP
        config file this module manages.
      '';
    };
  };

  config = mkIf cfg.enable {
    # `uvx` (from uv) fetches and runs the Python server on demand.
    home.packages = [ cfg.package ];

    # Declaratively own the Claude desktop MCP config. Use an absolute path to
    # uvx — the app launches servers with a minimal PATH that lacks the nix
    # profile bin dir.
    home.file.${cfg.configPath}.text = builtins.toJSON {
      mcpServers.apple-mail = {
        command = "${cfg.package}/bin/uvx";
        args = [ "mcp-apple-mail" ] ++ optional cfg.readOnly "--read-only";
      };
    };
  };
}
