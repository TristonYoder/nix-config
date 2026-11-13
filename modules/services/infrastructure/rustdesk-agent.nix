{ config, lib, pkgs, ... }:

# Unattended RustDesk agent: the root `rustdesk --service` unit, pointed at
# CortenDesk on pits (cortendesk.nix), plus a provisioning oneshot that sets
# unattended defaults, sets the fleet permanent password, and enrolls the
# device in the console. No one has to touch the machine.
#
# - Password: the agenix secret rustdesk-fleet-password, one for every host.
#   Approve mode is password-only, so incoming sessions never wait for a click.
#   The same password is the default on the console's shared "Fleet" address
#   book, so operators connect from it without typing it.
# - Enrollment: POSTs what `rustdesk --assign` would to
#   <apiServer>/api/devices/cli, with a CortenDesk API token (agenix secret
#   rustdesk-enroll-token, device + address_book rw). A device-rw token
#   registers the device pre-approved, in device group `deviceGroup`, and adds
#   it to address book `addressBook`. Both must exist in the console.
# - Wayland (Plasma) hosts need a one-time screen-share consent on the local
#   display before the first remote view; X11 hosts and terminal sessions need
#   nothing.

with lib;
let
  cfg = config.modules.services.infrastructure.rustdeskAgent;
  rd = "${cfg.package}/bin/rustdesk";

  options' = {
    custom-rendezvous-server = cfg.server;
    relay-server = cfg.server;
    api-server = cfg.apiServer;
    key = cfg.key;
    verification-method = "use-permanent-password";
    approve-mode = "password";
  } // optionalAttrs cfg.headless { allow-linux-headless = "Y"; }
    // cfg.extraOptions;
in
{
  options.modules.services.infrastructure.rustdeskAgent = {
    enable = mkEnableOption "unattended RustDesk agent enrolled in CortenDesk";

    package = mkOption {
      type = types.package;
      default = pkgs.rustdesk-flutter;
      defaultText = literalExpression "pkgs.rustdesk-flutter";
      description = "RustDesk client package.";
    };

    server = mkOption {
      type = types.str;
      default = "remote.theyoder.family";
      description = "ID/rendezvous and relay server host.";
    };

    apiServer = mkOption {
      type = types.str;
      default = "https://${cfg.server}";
      description = "CortenDesk console / client API URL. Also the enrollment endpoint.";
    };

    key = mkOption {
      type = types.str;
      # Same as home/modules/rustdesk.nix: the server's public key, not a secret.
      default = "BTZxuh2rmspuGFZUrPIw3cG5u95FXr6xrcoScaekXWc=";
      description = "Server public key.";
    };

    headless = mkOption {
      type = types.bool;
      default = false;
      description = "Allow sessions when no one is logged in to a graphical session (allow-linux-headless).";
    };

    extraOptions = mkOption {
      type = types.attrsOf types.str;
      default = { };
      example = { enable-file-transfer = "N"; };
      description = "Further RustDesk options, set with `rustdesk --option`.";
    };

    passwordFile = mkOption {
      type = types.str;
      default = config.age.secrets.rustdesk-fleet-password.path;
      defaultText = literalExpression "config.age.secrets.rustdesk-fleet-password.path";
      description = "Permanent password for unattended access.";
    };

    enroll = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Register the device in CortenDesk.";
      };

      tokenFile = mkOption {
        type = types.str;
        default = config.age.secrets.rustdesk-enroll-token.path;
        defaultText = literalExpression "config.age.secrets.rustdesk-enroll-token.path";
        description = "CortenDesk API token with device (and address_book) rw.";
      };

      deviceGroup = mkOption {
        type = types.nullOr types.str;
        default = "Fleet";
        description = "Console device group to file the device under.";
      };

      addressBook = mkOption {
        type = types.nullOr types.str;
        default = "Fleet";
        description = "Shared address book to add the device to, with the fleet password.";
      };

      tag = mkOption {
        type = types.nullOr types.str;
        default = "nixos";
        description = "Address book tag for the entry.";
      };
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    # nixpkgs ships no unit; this mirrors upstream's res/rustdesk.service.
    systemd.services.rustdesk = {
      description = "RustDesk";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "systemd-user-sessions.service" ];
      # The service starts `rustdesk --server` in the active session through
      # sudo, and finds that session with loginctl, ps and shell tools.
      path = [ "/run/wrappers" ] ++ (with pkgs; [
        coreutils gnugrep gnused gawk procps util-linux config.systemd.package bash
      ]);
      serviceConfig = {
        ExecStart = "${rd} --service";
        ExecStop = "${pkgs.procps}/bin/pkill -f \"rustdesk --\"";
        KillMode = "mixed";
        TimeoutStopSec = 30;
        LimitNOFILE = 100000;
        Restart = "always";
        RestartSec = 5;
      };
    };

    systemd.services.rustdesk-provision = {
      description = "Configure RustDesk for unattended access";
      wantedBy = [ "multi-user.target" ];
      after = [ "rustdesk.service" "network-online.target" "tailscaled.service" ];
      wants = [ "network-online.target" ];
      requires = [ "rustdesk.service" ];
      # Re-run when the wanted settings change, not just at boot.
      restartTriggers = [ (builtins.toJSON options') (builtins.toJSON cfg.enroll) ];
      path = with pkgs; [ coreutils curl jq hostname ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        StateDirectory = "rustdesk-agent";
        RuntimeDirectory = "rustdesk-provision";
        RuntimeDirectoryMode = "0700";
        UMask = "0077";
        # The console can be briefly unreachable at boot (Tailscale coming up).
        Restart = "on-failure";
        RestartSec = 60;
      };
      script = ''
        set -euo pipefail

        # --get-id goes over IPC to the service; empty until it is listening.
        id=""
        for _ in $(seq 1 60); do
          id=$(${rd} --get-id 2>/dev/null | tail -n1 || true)
          [ -n "$id" ] && break
          sleep 2
        done
        [ -n "$id" ] || { echo "RustDesk service not answering" >&2; exit 1; }
        echo "RustDesk ID $id"

        ${concatStrings (mapAttrsToList (k: v: ''
          if [ "$(${rd} --option ${escapeShellArg k} 2>/dev/null | tail -n1)" != ${escapeShellArg v} ]; then
            ${rd} --option ${escapeShellArg k} ${escapeShellArg v}
            echo "set ${k}"
          fi
        '') options')}

        # Set every run so a wiped RustDesk config heals itself. The password
        # is in argv for the moment this runs; the CLI has no other way in.
        out=$(${rd} --password "$(cat ${escapeShellArg cfg.passwordFile})" 2>&1 || true)
        case "$out" in *Done*|"") echo "permanent password set" ;; *) echo "$out" >&2; exit 1 ;; esac

        ${optionalString cfg.enroll.enable ''
          stamp=/var/lib/rustdesk-agent/enrolled
          if [ "$(cat "$stamp" 2>/dev/null || true)" = "$id" ]; then
            echo "already enrolled"
            exit 0
          fi
          host=$(hostname)
          # Same uuid the client sends: base64 of the machine id.
          uuid=$(printf %s "$(cat /etc/machine-id)" | base64 -w0)
          body=$RUNTIME_DIRECTORY/body.json
          hdr=$RUNTIME_DIRECTORY/auth
          jq -n --arg id "$id" --arg uuid "$uuid" --arg host "$host" \
            --rawfile pw ${escapeShellArg cfg.passwordFile} '
            { id: $id, uuid: $uuid, device_name: $host }
            ${optionalString (cfg.enroll.deviceGroup != null) "+ { device_group_name: ${builtins.toJSON cfg.enroll.deviceGroup} }"}
            ${optionalString (cfg.enroll.addressBook != null) ''
              + { address_book_name: ${builtins.toJSON cfg.enroll.addressBook},
                  address_book_alias: $host,
                  address_book_password: ($pw | rtrimstr("\n")) }
              ${optionalString (cfg.enroll.tag != null) "+ { address_book_tag: ${builtins.toJSON cfg.enroll.tag} }"}
            ''}' > "$body"
          printf 'Authorization: Bearer %s\n' "$(tr -d '[:space:]' < ${escapeShellArg cfg.enroll.tokenFile})" > "$hdr"
          # Empty 200 = success; any body is the error text.
          resp=$(curl -sS --retry 5 --retry-all-errors --retry-delay 5 \
            -o - -w '\n%{http_code}' -H @"$hdr" -H 'Content-Type: application/json' \
            --data-binary @"$body" ${escapeShellArg "${cfg.apiServer}/api/devices/cli"})
          rm -f "$body" "$hdr"
          code=''${resp##*$'\n'}
          msg=''${resp%$'\n'*}
          if [ "$code" = 200 ] && [ -z "$msg" ]; then
            printf %s "$id" > "$stamp"
            echo "enrolled in CortenDesk"
          else
            echo "enrollment failed ($code): $msg" >&2
            exit 1
          fi
        ''}
      '';
    };
  };
}
