{ config, lib, pkgs, ... }:

{
  # Auto-deployment service for GitHub Actions
  systemd.services.nixos-auto-deploy = {
    description = "Auto-deploy NixOS configuration from GitHub";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" "tailscale.service" ];
    
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      WorkingDirectory = "/tmp/nixos-config";
      ExecStart = pkgs.writeShellScript "auto-deploy" ''
        set -euo pipefail
        
        # Configuration
        REPO_URL="https://github.com/${{ secrets.GITHUB_REPO_OWNER }}/${{ secrets.GITHUB_REPO_NAME }}.git"
        DEPLOY_DIR="/tmp/nixos-config"
        BACKUP_DIR="/var/lib/nixos-backups"
        
        # Create backup directory
        mkdir -p "$BACKUP_DIR"
        
        # Backup current configuration
        if [ -d "/etc/nixos" ]; then
          BACKUP_NAME="nixos-backup-$(date +%Y%m%d-%H%M%S)"
          cp -r /etc/nixos "$BACKUP_DIR/$BACKUP_NAME"
          echo "Configuration backed up to $BACKUP_DIR/$BACKUP_NAME"
        fi
        
        # Clone/update repository
        if [ -d "$DEPLOY_DIR" ]; then
          cd "$DEPLOY_DIR"
          git fetch origin
          git reset --hard origin/main
        else
          git clone "$REPO_URL" "$DEPLOY_DIR"
          cd "$DEPLOY_DIR"
        fi
        
        # Test configuration
        echo "Testing configuration..."
        nix flake check --show-trace
        nixos-rebuild dry-run --flake .#david --show-trace
        
        # Deploy if test passes
        echo "Deploying configuration..."
        nixos-rebuild switch --flake .#david --show-trace
        
        # Cleanup old backups (keep last 10)
        cd "$BACKUP_DIR"
        ls -t | tail -n +11 | xargs -r rm -rf
        
        echo "Deployment completed successfully"
      '';
    };
  };

  # GitHub Actions deployment user
  users.users.github-deploy = {
    isSystemUser = true;
    group = "github-deploy";
    home = "/var/lib/github-deploy";
    createHome = true;
    shell = pkgs.bash;
  };
  
  users.groups.github-deploy = {};

  # Allow github-deploy user to run nixos-rebuild
  security.sudo.extraRules = [
    {
      users = [ "github-deploy" ];
      commands = [
        {
          command = "${pkgs.nixos-rebuild}/bin/nixos-rebuild";
          options = [ "NOPASSWD" ];
        }
        {
          command = "${pkgs.git}/bin/git";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  # Ensure required packages are available
  environment.systemPackages = with pkgs; [
    git
    nixos-rebuild
    jq
    rsync
  ];

  # Network configuration for GitHub Actions
  networking.firewall.allowedTCPPorts = [ 22 ];
  
  # SSH configuration for GitHub Actions
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PubkeyAuthentication = true;
      PermitRootLogin = "no";
      AllowUsers = [ "github-deploy" ];
    };
  };

  # Tailscale configuration for GitHub Actions access
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "both";
    extraUpFlags = [
      "--ssh"
      "--advertise-routes=10.150.0.0/16"
      "--advertise-exit-node"
      "--snat-subnet-routes=false"
      "--accept-routes=false"
    ];
  };

  # Auto-cleanup service for temporary files
  systemd.services.nixos-cleanup = {
    description = "Cleanup temporary NixOS deployment files";
    wantedBy = [ "multi-user.target" ];
    
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      ExecStart = pkgs.writeShellScript "cleanup" ''
        # Clean up old temporary files
        find /tmp -name "nixos-*" -type d -mtime +7 -exec rm -rf {} + 2>/dev/null || true
        find /var/tmp -name "nixos-*" -type d -mtime +7 -exec rm -rf {} + 2>/dev/null || true
        
        # Clean up old Nix store generations
        nix-collect-garbage -d
        
        echo "Cleanup completed"
      '';
    };
  };

  # Run cleanup weekly
  systemd.timers.nixos-cleanup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "weekly";
      Persistent = true;
    };
  };
}
