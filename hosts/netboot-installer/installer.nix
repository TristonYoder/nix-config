# Generic PXE/netboot installer image, served from david.
#
# Unlike the per-host ISO installers, this one isn't tied to a specific
# machine — it's the same "install any x86_64 host with zero physical
# media" tool the USB stick used to be, just reachable over the network.
#
# Build outputs consumed by modules/services/infrastructure/netboot.nix on
# david: config.system.build.kernel, config.system.build.netbootRamdisk,
# config.system.build.squashfsStore.

{ lib, modulesPath, ... }:
{
  imports = [
    (modulesPath + "/installer/netboot/netboot-minimal.nix")
  ];

  # SSH key handoff on first boot, same pattern used for live-USB installs —
  # no password prompt, no manual authorized_keys editing required.
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = lib.mkForce "yes";
  };

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK5JWm3A5tXTCPq8YTua30QH2+Pa/Mz96QC5KJZKdEsz"
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDv25/0nLCy/VRqOYPu10PA5lUcireG1GEUk1+mFMPbL7q7o+9GqJ8INhlncvd6tc5sm5ZblK5aqrZxKW8Cy78OZpPfPTyVWVIcxos+SWba1Fbi+Xco0ZT3BqRvCcgkLM/jCIVfr5Hzo2iP5lvt21KN2OY7XpwlqdCfmZyyjwPGwFfniEbwvHZSaxgSllXqTcLrpYt75ryn58T7HKF0m7vCGguct62UtKibLUw0jsgFk5rbXGqggGOH7W/Gg0gnzCN5eB3azbpFvRMW106lMz7iXIy1ZyfeQrGATH+TlEgYsU/ROk2LSQOun99DqJOAts6ZaeFu5+VDsJh0S17tIud5"
  ];

  networking.firewall.enable = false;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
}
