# Configuration for plotiphar-imac - 2019 iMac (x86_64) Plotiphar signage kiosk
#
# Same kiosk role as stage-plotiphar (profiles/kiosk.nix): one fullscreen
# Chromium per connected display, pairing at https://plotiphar.com/pair. The
# iMac is its own screen, so no Output Device / CEC bridge.
#
# WiFi: Broadcom BCM4364 (iMac19,2), see the WIFI section below.

{ config, pkgs, lib, ... }:
{
  networking.hostName = "plotiphar-imac";
  system.stateVersion = "26.05";

  # =============================================================================
  # MAINTENANCE
  # =============================================================================

  # Nightly reboot, as on stage-plotiphar: clears Chromium/GPU leaks on an
  # unattended display and re-runs the launcher's output detection.
  systemd.services.nightly-reboot = {
    description = "Nightly reboot";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${config.systemd.package}/bin/systemctl reboot";
    };
  };
  systemd.timers.nightly-reboot = {
    description = "Reboot nightly at 04:00";
    wantedBy = [ "timers.target" ];
    timerConfig.OnCalendar = "*-*-* 04:00:00";
  };

  # =============================================================================
  # NETWORK
  # =============================================================================

  networking.useDHCP = lib.mkDefault true;

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
  };

  # =============================================================================
  # WIFI
  # =============================================================================

  # brcmfmac has no firmware for this chip; Apple ships it inside macOS. It
  # was copied off this iMac's own macOS install (before it was wiped) and
  # renamed with the t2linux/Asahi script, into /var/lib/apple-wifi-firmware.
  # Kept on the host, not in this public repo: it's Apple's firmware.
  #
  # The DSDT picks the board name by Apple board ID ("nihau" here), but via a
  # _DSM brcmfmac doesn't read, so the driver asks for the generic names.
  # Those are symlinks in that directory to the nihau set with the "m"
  # antenna NVRAM -- the combination that initializes on this board.
  #
  # To redo it from macOS files: t2linux firmware.sh `rename_only`, then:
  #   G=brcmfmac4364b2-pcie
  #   ln -sf $G.apple,nihau.bin $G.bin
  #   ln -sf $G.apple,nihau-HRPN-m.txt $G.txt
  #   ln -sf $G.apple,nihau.clm_blob $G.clm_blob
  #   ln -sf $G.apple,nihau.txcap_blob $G.txcap_blob
  boot.kernelParams = [ "firmware_class.path=/var/lib/apple-wifi-firmware" ];

  age.secrets.plotiphar-imac-wifi-psk = {
    file = ../../secrets/plotiphar-imac-wifi-psk.age;
    mode = "0400";
  };

  networking.networkmanager.ensureProfiles = {
    environmentFiles = [ config.age.secrets.plotiphar-imac-wifi-psk.path ];
    profiles."Mission-Church-AV" = {
      connection = {
        id = "Mission-Church-AV";
        type = "wifi";
      };
      wifi = {
        mode = "infrastructure";
        ssid = "Mission-Church-AV";
      };
      wifi-security = {
        key-mgmt = "wpa-psk";
        # Substituted from the agenix environmentFile at activation.
        psk = "$WIFI_PSK";
      };
      ipv4.method = "auto";
      ipv6.method = "auto";
    };
  };
}
