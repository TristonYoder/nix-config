{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.hardware.t2Suspend;
in
{
  options.modules.hardware.t2Suspend = {
    enable = mkEnableOption "T2 Mac power management (sleep/hibernate workarounds)";

    mode = mkOption {
      type = types.enum [ "disabled" "workaround" ];
      default = "disabled";
      description = ''
        T2 Mac power management mode (requires enable = true).

        disabled   - all sleep/hibernate blocked; lid and sleep key lock the screen
        workaround - suspend enabled via apple_bce unload/reload trick; hibernate
                     and hybrid-sleep blocked; lid and sleep key trigger suspend
      '';
    };
  };

  config = mkIf cfg.enable (mkMerge [
    # ── disabled ────────────────────────────────────────────────────────────
    (mkIf (cfg.mode == "disabled") {
      systemd.sleep.settings.Sleep = {
        AllowSuspend = false;
        AllowHibernation = false;
        AllowSuspendThenHibernate = false;
        AllowHybridSleep = false;
      };

      services.logind = {
        lidSwitch = "lock";
        lidSwitchExternalPower = "lock";
        settings.Login = {
          HandleSuspendKey = "lock";
          HandleHibernateKey = "ignore";
        };
      };
    })

    # ── workaround ───────────────────────────────────────────────────────────
    (mkIf (cfg.mode == "workaround") {
      # Required for deep suspend to work on T2 hardware.
      boot.kernelParams = [
        "intel_iommu=on"
        "iommu=pt"
        "pm_async=off"
        "mem_sleep_default=deep"
      ];

      # apple_bce drives the T2 keyboard, Touch Bar, and audio. It wedges the
      # suspend path, so unload it before sleep and reload after resume.
      # Expected resume behaviour: screen returns first, then ~3 s later the
      # keyboard, trackpad, and Touch Bar come back as apple_bce finishes
      # reinitialising. This is normal — not a bug.
      systemd.services.t2-suspend-fix = {
        description = "Unload apple-bce before sleep, reload after resume";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.kmod}/bin/rmmod -f apple_bce";
          ExecStop = "${pkgs.kmod}/bin/modprobe apple_bce";
        };
        # wantedBy: start this service when sleep.target activates (pre-sleep)
        # partOf: stop this service when sleep.target deactivates (post-resume),
        #         which triggers ExecStop = modprobe apple_bce
        wantedBy = [ "sleep.target" ];
        before = [ "sleep.target" ];
        partOf = [ "sleep.target" ];
      };

      # Suspend works (with the service above); hibernate and hybrid-sleep do not.
      systemd.sleep.settings.Sleep = {
        AllowSuspend = true;
        AllowHibernation = false;
        AllowSuspendThenHibernate = false;
        AllowHybridSleep = false;
      };

      services.logind = {
        lidSwitch = "suspend";
        lidSwitchExternalPower = "suspend";
        settings.Login = {
          HandleSuspendKey = "suspend";
          HandleHibernateKey = "ignore";
        };
      };
    })
  ]);
}
