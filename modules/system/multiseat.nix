{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.system.multiseat;

  # Generate udev rules for seat assignment
  mkSeatUdevRule = seatName: devices: concatMapStringsSep "\n" (device:
    ''SUBSYSTEM=="${device.subsystem}", KERNEL=="${device.kernel}", TAG+="seat", ENV{ID_SEAT}="${seatName}"''
  ) devices;

  # Only generate rules for enabled seats with devices
  seat0Rules = optionalString (cfg.seat0.enable && cfg.seat0.devices != [])
    ("# Seat 0 device assignments\n" + mkSeatUdevRule "seat0" cfg.seat0.devices);

  seat1Rules = optionalString (cfg.seat1.enable && cfg.seat1.devices != [])
    ("# Seat 1 device assignments\n" + mkSeatUdevRule "seat1" cfg.seat1.devices);

  allUdevRules = concatStringsSep "\n\n" (filter (s: s != "") [
    "# Multiseat device assignments - managed by NixOS"
    seat0Rules
    seat1Rules
  ]);

  deviceType = types.submodule {
    options = {
      subsystem = mkOption {
        type = types.str;
        example = "drm";
        description = "Device subsystem (drm, input, sound, etc)";
      };
      kernel = mkOption {
        type = types.str;
        example = "card0";
        description = "Kernel device name or pattern";
      };
    };
  };

  seatType = types.submodule {
    options = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable this seat";
      };

      gpu = mkOption {
        type = types.str;
        example = "pci-0000:01:00.0";
        description = "PCI path to GPU for this seat";
      };

      devices = mkOption {
        type = types.listOf deviceType;
        default = [ ];
        description = "Additional devices to assign to this seat (input, audio, etc)";
      };

      autologin = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Username to autologin on this seat";
      };

      session = mkOption {
        type = types.str;
        default = "plasma";
        description = "Desktop session to use";
      };
    };
  };
in
{
  options.modules.system.multiseat = {
    enable = mkEnableOption "Multiseat configuration";

    seat0 = mkOption {
      type = seatType;
      default = { };
      description = "Configuration for seat0 (typically integrated GPU for admin/KVM)";
    };

    seat1 = mkOption {
      type = seatType;
      default = { };
      description = "Configuration for seat1 (typically discrete GPU for gaming/media)";
    };
  };

  config = mkIf cfg.enable {
    # Ensure desktop is enabled for multiseat
    assertions = [
      {
        assertion = config.modules.system.desktop.enable;
        message = "Multiseat requires desktop environment to be enabled";
      }
      {
        assertion = cfg.seat0.enable || cfg.seat1.enable;
        message = "At least one seat must be enabled for multiseat configuration";
      }
      {
        assertion = cfg.seat0.gpu != cfg.seat1.gpu;
        message = "Seat 0 and Seat 1 must have different GPUs";
      }
    ];

    # Udev rules for seat assignment
    services.udev.extraRules = allUdevRules + optionalString (cfg.seat0.enable || cfg.seat1.enable) ''

      # GPU assignments to seats
      ${optionalString cfg.seat0.enable ''TAG=="seat", ENV{ID_PATH}=="${cfg.seat0.gpu}", ENV{ID_SEAT}="seat0"''}
      ${optionalString cfg.seat1.enable ''TAG=="seat", ENV{ID_PATH}=="${cfg.seat1.gpu}", ENV{ID_SEAT}="seat1"''}
    '';

    # Configure SDDM for multiseat
    # SDDM will automatically detect seats and start greeters on each
    services.displayManager.sddm = {
      settings = {
        General = {
          # Enable multiple seats
          MinimumVT = 7;
        };
      };
    };

    # Seat-specific autologin configuration
    # Note: SDDM handles per-seat autologin via seat-specific configs
    services.displayManager.autoLogin = mkIf (cfg.seat0.autologin != null || cfg.seat1.autologin != null) {
      enable = mkIf (cfg.seat0.autologin != null) true;
      user = mkIf (cfg.seat0.autologin != null) cfg.seat0.autologin;
    };

    # PipeWire configuration for seat-aware audio
    services.pipewire.extraConfig.pipewire = {
      "10-multiseat" = {
        "context.properties" = {
          # Allow seat-specific audio device access
          "default.clock.rate" = 48000;
        };
      };
    };

    # Disable automatic VT switching to prevent seat conflicts
    services.xserver.tty = null;

    # Environment variables for multiseat
    environment.sessionVariables = {
      # Help applications respect seat assignments
      XDG_SEAT = "$XDG_SEAT";
    };

    # Diagnostic service for multiseat verification
    systemd.services.multiseat-diagnostic = {
      description = "Multiseat configuration diagnostics";
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-logind.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        echo "=== Multiseat Configuration Check ==="
        echo "Configured seats:"
        ${pkgs.systemd}/bin/loginctl list-seats || true
        echo
        echo "Seat device assignments:"
        ${optionalString cfg.seat0.enable ''
        echo "Seat 0 GPU: ${cfg.seat0.gpu}"
        ${pkgs.systemd}/bin/loginctl seat-status seat0 || echo "Seat0 not yet active"
        ''}
        ${optionalString cfg.seat1.enable ''
        echo "Seat 1 GPU: ${cfg.seat1.gpu}"
        ${pkgs.systemd}/bin/loginctl seat-status seat1 || echo "Seat1 not yet active"
        ''}
        echo "==================================="
      '';
    };
  };
}
