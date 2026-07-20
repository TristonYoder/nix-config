# Apple Mail MCP server (patrickfreyer/apple-mail-mcp)
#
# Makes the `mcp-apple-mail` server runnable via `uvx` by installing `uv`.
# It deliberately does NOT manage the Claude desktop config
# (claude_desktop_config.json) — that file is the app's live preferences store
# and is left entirely to the user. Register the server yourself, e.g.:
#
#   claude mcp add apple-mail -- uvx mcp-apple-mail
#
# or add this to the app's config manually:
#
#   "mcpServers": { "apple-mail": { "command": "uvx", "args": ["mcp-apple-mail"] } }
#
# Home Manager module. Import + enable it in a user's home config:
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
    enable = mkEnableOption "Apple Mail MCP server runtime (uv/uvx) for the Claude desktop app";

    package = mkOption {
      type = types.package;
      default = pkgs.uv;
      defaultText = literalExpression "pkgs.uv";
      description = "The uv package providing `uvx`, used to fetch and run mcp-apple-mail.";
    };
  };

  config = mkIf cfg.enable {
    # `uvx` (from uv) fetches and runs the Python server on demand. The Claude
    # desktop config is intentionally left untouched — register the server there
    # manually (see the header comment).
    home.packages = [ cfg.package ];
  };
}
