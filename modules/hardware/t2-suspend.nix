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
      systemd.sleep.extraConfig = ''
        AllowSuspend=no
        AllowHibernation=no
        AllowSuspendThenHibernate=no
        AllowHybridSleep=no
      '';

      services.logind = {
        lidSwitch = "lock";
        lidSwitchExternalPower = "lock";
        extraConfig = ''
          HandleSuspendKey=lock
          HandleHibernateKey=ignore
        '';
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
      # Resume takes ~30 s while the module reinitialises.
      systemd.services.t2-suspend-fix = {
        description = "Unload apple-bce before sleep, reload after resume";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.kmod}/bin/rmmod -f apple_bce";
          ExecStop = "${pkgs.kmod}/bin/modprobe apple_bce";
        };
        wantedBy = [ "sleep.target" ];
        before = [ "sleep.target" ];
      };

      # Suspend works (with the service above); hibernate and hybrid-sleep do not.
      systemd.sleep.extraConfig = ''
        AllowSuspend=yes
        AllowHibernation=no
        AllowSuspendThenHibernate=no
        AllowHybridSleep=no
      '';

      services.logind = {
        lidSwitch = "suspend";
        lidSwitchExternalPower = "suspend";
        extraConfig = ''
          HandleSuspendKey=suspend
          HandleHibernateKey=ignore
        '';
      };
    })
  ]);
}
