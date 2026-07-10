{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.development.githubRunner;

  runnerModule = types.submodule {
    options = {
      url = mkOption {
        type = types.str;
        description = ''
          Repository or organization URL to register this runner against.
          Use an org URL only if `tokenFile` contains an org-wide token — a
          repo-scoped token needs the full repo URL.
        '';
        example = "https://github.com/TristonYoder/stagePlotiphar";
      };

      tokenFile = mkOption {
        type = types.path;
        description = ''
          Path to a file containing a GitHub fine-grained PAT (preferred) or
          a one-hour runner registration token. Darwin has no agenix
          integration in this repo, so this must be a plain out-of-store
          path you create manually (e.g. under ~/.config/github-runners/),
          never a path inside the repo.
        '';
      };

      extraLabels = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Extra labels for this runner, in addition to the defaults.";
      };

      replace = mkOption {
        type = types.bool;
        default = true;
        description = "Replace any existing runner registered under the same name.";
      };

      ephemeral = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Deregister after every job. Only safe when `tokenFile` contains a
          PAT — the runner re-registers itself on the next launchd start
          since its state directory is gone after deregistration.
        '';
      };

      extraPackages = mkOption {
        type = types.listOf types.package;
        default = [ ];
        description = "Extra packages available on PATH to workflow jobs.";
      };
    };
  };

  runnerDir = name: "${config.users.users.${config.system.primaryUser}.home}/Projects/github-runners/${name}";

  mkRunnerAgent = name: runner:
    let
      installDir = runnerDir name;
      label = "family.theyoder.github-runner.${name}";
      pathDirs = [ "/usr/bin" "/bin" "/usr/sbin" "/sbin" "/nix/var/nix/profiles/default/bin" ]
        ++ map (p: "${p}/bin") ([ pkgs.bashInteractive pkgs.coreutils pkgs.git pkgs.gnutar pkgs.gzip pkgs.github-runner ] ++ runner.extraPackages);

      runScript = pkgs.writeShellScript "github-runner-${name}" ''
        set -euo pipefail
        mkdir -p ${escapeShellArg installDir}
        cd ${escapeShellArg installDir}

        # Only configure on first run (or after a deregistration wiped .runner).
        # To force re-registration after changing url/labels, remove this
        # directory manually before the agent next starts.
        if [ ! -f .runner ]; then
          token=$(cat ${escapeShellArg runner.tokenFile})
          args=(
            --unattended --disableupdate
            --url ${escapeShellArg runner.url}
            --labels ${escapeShellArg (concatStringsSep "," runner.extraLabels)}
            --name ${escapeShellArg name}
            --work _work
            ${optionalString runner.replace "--replace"}
            ${optionalString runner.ephemeral "--ephemeral"}
          )
          if [[ "$token" == ghp_* || "$token" == github_pat_* ]]; then
            args+=(--pat "$token")
          else
            args+=(--token "$token")
          fi
          "${pkgs.github-runner}/bin/Runner.Listener" configure "''${args[@]}"
        fi

        exec "${pkgs.github-runner}/bin/Runner.Listener" run --startuptype service
      '';
    in
    {
      enable = true;
      target = "${label}.plist";
      text = ''
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>${label}</string>

          <key>ProgramArguments</key>
          <array>
            <string>${runScript}</string>
          </array>

          <key>RunAtLoad</key>
          <true/>

          <key>KeepAlive</key>
          <dict>
            <key>SuccessfulExit</key>
            <false/>
            <key>Crashed</key>
            <true/>
          </dict>

          <key>ProcessType</key>
          <string>Background</string>

          <key>StandardErrorPath</key>
          <string>/tmp/${label}.err.log</string>

          <key>StandardOutPath</key>
          <string>/tmp/${label}.out.log</string>

          <key>EnvironmentVariables</key>
          <dict>
            <key>PATH</key>
            <string>${concatStringsSep ":" pathDirs}</string>
          </dict>
        </dict>
        </plist>
      '';
    };
in
{
  options.modules.services.development.githubRunner = {
    enable = mkEnableOption "Self-hosted GitHub Actions runner(s) (launchd-based)";

    runners = mkOption {
      type = types.attrsOf runnerModule;
      default = { };
      description = ''
        Named self-hosted runner instances to register on this host. Each
        runner's install/work directory lives under
        ~/Projects/github-runners/<name>.
      '';
      example = literalExpression ''
        {
          stageplotiphar = {
            url = "https://github.com/TristonYoder/stagePlotiphar";
            tokenFile = "/Users/tyoder/.config/github-runners/stageplotiphar.token";
          };
        }
      '';
    };
  };

  config = mkIf cfg.enable {
    environment.launchAgents = mapAttrs'
      (name: runner: nameValuePair "family.theyoder.github-runner.${name}" (mkRunnerAgent name runner))
      cfg.runners;
  };
}
