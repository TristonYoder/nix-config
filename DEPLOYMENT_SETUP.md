# NixOS Auto-Deployment Setup Guide

This guide will help you set up automated deployment of your NixOS configuration using GitHub Actions and Tailscale.

## Prerequisites

1. A NixOS server with Tailscale installed
2. A GitHub repository with your NixOS configuration
3. Tailscale OAuth credentials for GitHub Actions

## Server Setup

### 1. Install the deployment configuration

Add the server deployment configuration to your NixOS configuration:

```nix
# In your configuration.nix
imports = [
  ./server-deployment.nix
  # ... other imports
];
```

### 2. Configure Tailscale

Ensure Tailscale is properly configured on your server:

```bash
# Enable Tailscale
sudo systemctl enable tailscaled
sudo systemctl start tailscaled

# Connect to your Tailscale network
sudo tailscale up
```

### 3. Set up SSH keys for GitHub Actions

Create a dedicated user for GitHub Actions deployment:

```bash
# Create the user (this is handled by the NixOS configuration)
sudo useradd -m -s /bin/bash github-deploy

# Generate SSH key for GitHub Actions
sudo -u github-deploy ssh-keygen -t ed25519 -C "github-actions@your-server"
```

Add the public key to the server's authorized_keys:

```bash
sudo -u github-deploy mkdir -p /var/lib/github-deploy/.ssh
sudo -u github-deploy chmod 700 /var/lib/github-deploy/.ssh
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI..." | sudo -u github-deploy tee /var/lib/github-deploy/.ssh/authorized_keys
sudo -u github-deploy chmod 600 /var/lib/github-deploy/.ssh/authorized_keys
```

## GitHub Repository Setup

### 1. Create GitHub Secrets

Go to your repository settings → Secrets and variables → Actions, and add:

- `TAILSCALE_OAUTH_CLIENT_ID`: Your Tailscale OAuth client ID
- `TAILSCALE_OAUTH_SECRET`: Your Tailscale OAuth secret
- `SERVER_HOSTNAME`: Your server's Tailscale hostname (e.g., "david")
- `SERVER_USER`: SSH user for deployment (e.g., "github-deploy")
- `GITHUB_REPO_OWNER`: Your GitHub username or organization
- `GITHUB_REPO_NAME`: Your repository name

### 2. Tailscale OAuth Setup

1. Go to [Tailscale Admin Console](https://login.tailscale.com/admin/settings/oauth)
2. Create a new OAuth client
3. Set the redirect URI to: `https://github.com/settings/connections/applications/oauth`
4. Copy the client ID and secret to your GitHub secrets

### 3. Configure GitHub Actions

The workflows are already set up in `.github/workflows/`:

- `test-configuration.yml`: Tests configuration on branches and PRs
- `deploy-to-server.yml`: Deploys to server on main branch pushes

## Workflow Behavior

### Testing (All Branches and PRs)
- Runs `nix flake check` to validate the configuration
- Runs `nixos-rebuild dry-run` to test the build
- Sets GitHub status flags based on results

### Deployment (Main Branch Only)
- Tests configuration locally first
- Connects to server via Tailscale
- Copies configuration to server
- Runs `nixos-rebuild switch` on the server
- Sets deployment status flags

## Manual Deployment

You can also trigger deployment manually:

1. Go to Actions tab in your GitHub repository
2. Select "Deploy to NixOS Server" workflow
3. Click "Run workflow"
4. Select the branch to deploy

## Troubleshooting

### Common Issues

1. **Tailscale connection fails**
   - Ensure Tailscale is running on your server
   - Check that the OAuth credentials are correct
   - Verify the server hostname in secrets

2. **SSH connection fails**
   - Check that the SSH key is properly set up
   - Verify the server user has correct permissions
   - Ensure the server IP is correct

3. **NixOS rebuild fails**
   - Check the server logs: `journalctl -u nixos-auto-deploy`
   - Verify the configuration is valid
   - Check for missing dependencies

### Logs and Monitoring

View deployment logs on the server:

```bash
# View auto-deployment logs
sudo journalctl -u nixos-auto-deploy -f

# View system logs
sudo journalctl -f

# Check Tailscale status
tailscale status
```

## Security Considerations

1. **SSH Keys**: Use dedicated keys for GitHub Actions, not your personal keys
2. **Permissions**: The deployment user has limited sudo access
3. **Network**: Tailscale provides secure, encrypted connections
4. **Backups**: Old configurations are automatically backed up

## Backup and Recovery

The system automatically:
- Backs up configurations before deployment
- Keeps the last 10 backups
- Cleans up old temporary files weekly

To recover from a failed deployment:

```bash
# List available backups
ls -la /var/lib/nixos-backups/

# Restore from backup
sudo cp -r /var/lib/nixos-backups/nixos-backup-YYYYMMDD-HHMMSS /etc/nixos
sudo nixos-rebuild switch
```

## Advanced Configuration

### Custom Deployment Scripts

You can modify the deployment behavior by editing `server-deployment.nix`:

```nix
# Add custom pre-deployment hooks
ExecStartPre = pkgs.writeShellScript "pre-deploy" ''
  # Custom pre-deployment logic
  echo "Running pre-deployment checks..."
'';

# Add custom post-deployment hooks
ExecStartPost = pkgs.writeShellScript "post-deploy" ''
  # Custom post-deployment logic
  echo "Running post-deployment tasks..."
'';
```

### Multiple Server Deployment

To deploy to multiple servers, modify the GitHub Actions workflow to loop through server configurations:

```yaml
- name: Deploy to multiple servers
  run: |
    for server in server1 server2 server3; do
      # Deploy to each server
    done
```

## Support

For issues or questions:
1. Check the GitHub Actions logs
2. Review server logs
3. Verify Tailscale connectivity
4. Test SSH connection manually
