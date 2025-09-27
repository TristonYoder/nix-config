{ config, lib, pkgs, ... }:

{
  # GitHub Actions user for automated NixOS configuration testing and deployment
  users.users.github-actions = {
    isNormalUser = true;
    description = "GitHub Actions user for automated deployments";
    home = "/home/github-actions";
    shell = pkgs.bash;
    extraGroups = [ "wheel" ];
    # SSH keys for GitHub Actions
    openssh.authorizedKeys.keys = [
      # Add your GitHub Actions public key here
       "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJu9lBREFqV8dhEoTjma/muYKgs6nsjcKW3FVhe+t0Nu github-actions@david-nixos"
    ];
  };

  # Sudo permissions for GitHub Actions user
  security.sudo.extraRules = [
    {
      users = [ "github-actions" ];
      commands = [
        {
          command = "${pkgs.nixos-rebuild}/bin/nixos-rebuild";
          options = [ "NOPASSWD" ];
        }
        {
          command = "${pkgs.nix}/bin/nix";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/bin/cp";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/bin/mkdir";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/bin/chown";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/bin/chmod";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/bin/rm";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/bin/find";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/bin/xargs";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/bin/rsync";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/bin/tee";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/bin/cat";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/bin/echo";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/bin/date";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/bin/sleep";
          options = [ "NOPASSWD" ];
        }
        {
          command = "/bin/dig";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  # SSH is already configured in your main configuration
  # No additional SSH configuration needed since Tailscale handles secure connection

  # Create necessary directories for GitHub Actions
  systemd.tmpfiles.rules = [
    "d /var/backups/nixos 755 root root -"
    "d /var/log 755 root root -"
    "f /var/log/nixos-deploy.log 644 root root -"
  ];

  # Install required packages for GitHub Actions
  environment.systemPackages = with pkgs; [
    rsync
    dnsutils  # for dig command
    git
    bash
  ];

  # Firewall rules are already configured in your main configuration
  # Tailscale handles the secure connection, so no additional firewall rules needed
}