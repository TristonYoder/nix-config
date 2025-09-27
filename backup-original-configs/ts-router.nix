{ config, pkgs, ... }:

{
  # Container configuration
  containers.tailscale-router = {
    autoStart = true;
    ephemeral = true;
    privateNetwork = true;

    # Use a bridge instead of macvlan
    macvlans = [ "br0" ];

    config = { config, pkgs, ... }: {
      system.stateVersion = "23.11";

      # Network configuration
      networking = {
        useHostResolvConf = true;
        useDHCP = false; # Use a static IP for the container
        firewall.enable = false;

        # Static IP for the container
        interfaces.mv-br0 = {
          useDHCP = false;
          ipv4.addresses = [{
            address = "10.150.100.31"; # Unique container IP
            prefixLength = 23;
          }];
        };

        # Set the container's default gateway
        defaultGateway = {
          address = "10.150.100.1";
          interface = "mv-br0";
        };

        # Enable NAT
        nat = {
          enable = true;
          enableIPv6 = true;
        };
      };

      # Enable IP forwarding in the container
      boot.kernel.sysctl = {
        "net.ipv4.ip_forward" = 1;
        "net.ipv6.conf.all.forwarding" = 1;
      };

      # Enable and configure Tailscale
      services.tailscale = {
        enable = true;
        useRoutingFeatures = "both";
        extraUpFlags = [
"--ssh"
"--snat-subnet-routes=false"
"--accept-routes=true"
];};
      # Workaround for Wiregaurd Bug
      # https://github.com/NixOS/nixpkgs/issues/180175
#      systemd.services.NetworkManager-wait-online.enable = lib.mkForce false;
#      systemd.services.systemd-networkd-wait-online.enable = lib.mkForce false;

    
      # Required system packages
      environment.systemPackages = with pkgs; [
        tailscale
        iproute2
        iptables
      ];

      # Ensure Tailscale starts after the network
      systemd.services = {
        tailscale = {
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          wantedBy = [ "multi-user.target" ];
        };
      };
    };
  };

  # Host configuration
  networking = {
    # Create a bridge on the host
    bridges.br0.interfaces = [ "enp4s0f0" ];

    # Assign the host's IP to the bridge instead of enp4s0f0
    interfaces.br0.ipv4.addresses = [{
      address = "10.150.100.30"; # Host IP
      prefixLength = 23;
    }];

    # Default gateway for the host
    defaultGateway = {
      address = "10.150.100.1";
      interface = "br0";
    };

    # Enable NAT for internal interfaces
    nat = {
      enable = true;
      enableIPv6 = true;
      internalInterfaces = [ "ve-tailscale-router" ];
    };
  };

  # Kernel-level IP forwarding for the host
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };
}
