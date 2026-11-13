{ config, lib, pkgs, ... }:

# Points the RustDesk client at the self-hosted CortenDesk server on pits
# (modules/services/infrastructure/cortendesk.nix): ID/relay server plus the
# API server, which signs clients in and registers them in the console.
#
# RustDesk rewrites RustDesk2.toml itself, so it can't be a read-only store
# symlink. Activation merges only the server keys into [options] and leaves
# everything else (ID, peers, other settings) alone. A running client may
# overwrite the edit on exit; settings apply from the next launch.

with lib;
let
  cfg = config.modules.rustdesk;
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;

  configFile =
    if isDarwin
    then "${config.home.homeDirectory}/Library/Preferences/com.carriez.RustDesk/RustDesk2.toml"
    else "${config.xdg.configHome}/rustdesk/RustDesk2.toml";

  python = pkgs.python3.withPackages (ps: [ ps.tomlkit ]);

  options' = {
    custom-rendezvous-server = cfg.server;
    relay-server = cfg.server;
    api-server = cfg.apiServer;
  } // optionalAttrs (cfg.key != null) { key = cfg.key; };

  merge = pkgs.writeText "rustdesk-merge.py" ''
    import json, os, sys, tomlkit
    path, wanted = sys.argv[1], json.loads(sys.argv[2])
    doc = tomlkit.parse(open(path).read()) if os.path.exists(path) else tomlkit.document()
    opts = doc.setdefault("options", tomlkit.table())
    if all(opts.get(k) == v for k, v in wanted.items()):
        sys.exit(0)
    opts.update(wanted)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        f.write(tomlkit.dumps(doc))
    os.replace(tmp, path)
  '';
in
{
  options.modules.rustdesk = {
    enable = mkEnableOption "RustDesk client pointed at the self-hosted server";

    server = mkOption {
      type = types.str;
      default = "remote.theyoder.family";
      description = "ID/rendezvous and relay server host.";
    };

    apiServer = mkOption {
      type = types.str;
      default = "https://${cfg.server}";
      description = "CortenDesk console / client API URL.";
    };

    key = mkOption {
      type = types.nullOr types.str;
      # CortenDesk server public key (pits:/var/lib/cortendesk/rustdesk/id_ed25519.pub).
      # Not a secret; the private half is the agenix secret cortendesk-private-key.
      default = "BTZxuh2rmspuGFZUrPIw3cG5u95FXr6xrcoScaekXWc=";
      description = "Server public key. Without it clients still connect, but can't verify the server.";
    };
  };

  config = mkIf cfg.enable {
    home.activation.rustdeskServer = hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${python}/bin/python3 ${merge} ${escapeShellArg configFile} ${escapeShellArg (builtins.toJSON options')}
    '';
  };
}
