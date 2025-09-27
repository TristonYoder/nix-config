# NixOS GitHub Actions Integration

This repository includes automated testing and deployment of NixOS configurations using GitHub Actions and Tailscale.

## Features

- ✅ **Automated Testing**: Test NixOS configurations on every push and pull request
- ✅ **Branch Testing**: Test all branches (main, develop, feature/*, bugfix/*)
- ✅ **Automatic Deployment**: Deploy to production when main branch tests pass
- ✅ **Rollback Support**: Automatic configuration backups with rollback capability
- ✅ **Tailscale Integration**: Secure connection to your server via Tailscale
- ✅ **Minimal Server Changes**: No need to overhaul your existing NixOS setup

## Architecture

```
GitHub Repository → GitHub Actions → Tailscale → Your NixOS Server
```

1. **GitHub Actions** triggers on code changes
2. **Tailscale** provides secure connection to your server
3. **GitHub Actions** handles all deployment logic
4. **Backup System** ensures rollback capability

## Setup Instructions

### 1. Server Preparation

The GitHub Actions user and permissions are now declared in NixOS configuration. Simply run:

```bash
# Apply the NixOS configuration (this creates the github-actions user and permissions)
sudo nixos-rebuild switch

# Add your GitHub Actions public key
echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... github-actions@your-repo' >> /home/github-actions/.ssh/authorized_keys
chown github-actions:github-actions /home/github-actions/.ssh/authorized_keys
chmod 600 /home/github-actions/.ssh/authorized_keys
```

### 2. GitHub Repository Secrets

Configure the following secrets in your GitHub repository:

| Secret Name | Description | Example |
|-------------|-------------|---------|
| `TAILSCALE_OAUTH_CLIENT_ID` | Tailscale OAuth Client ID | `client_1234567890abcdef` |
| `TAILSCALE_OAUTH_SECRET` | Tailscale OAuth Secret | `secret_abcdef1234567890` |
| `NIXOS_SERVER_HOSTNAME` | Your server's Tailscale hostname | `david` |
| `NIXOS_SERVER_USER` | SSH user for GitHub Actions | `github-actions` |

### 3. Tailscale OAuth Setup

1. Go to [Tailscale Admin Console](https://login.tailscale.com/admin/settings/oauth)
2. Create a new OAuth client
3. Set the redirect URI to: `https://github.com/your-username/your-repo`
4. Copy the Client ID and Secret to GitHub secrets

### 4. SSH Key Setup

Generate an SSH key pair for GitHub Actions:

```bash
# Generate SSH key
ssh-keygen -t ed25519 -C "github-actions@your-repo" -f ~/.ssh/github_actions

# Copy public key to server
ssh-copy-id -i ~/.ssh/github_actions.pub github-actions@your-server.ts.net
```

Add the private key to GitHub repository secrets as `SSH_PRIVATE_KEY`.

## Workflow Details

### Test Workflow (`test-nixos-config.yml`)

**Triggers:**
- Push to any branch
- Pull requests to main

**Process:**
1. Connects to server via Tailscale
2. Copies configuration files
3. Runs `nixos-rebuild dry-run`
4. Reports success/failure status

### Deploy Workflow (`deploy-nixos-config.yml`)

**Triggers:**
- Push to main branch (after successful tests)
- Manual trigger

**Process:**
1. Creates configuration backup
2. Copies new configuration
3. Runs final test
4. Executes `nixos-rebuild switch`
5. Reports deployment status

## Backup System

The system automatically creates backups in `/var/backups/nixos/` with the following structure:

```
/var/backups/nixos/
├── config_20240101_120000/
│   ├── configuration.nix
│   ├── apps.nix
│   └── docker/
└── config_20240101_130000/
    ├── configuration.nix
    └── ...
```

- **Retention**: Keeps last 10 backups automatically
- **Rollback**: Manual rollback by copying backup files back to `/etc/nixos/`

## Troubleshooting

### Common Issues

1. **Tailscale Connection Failed**
   - Check Tailscale OAuth credentials
   - Verify server hostname in secrets
   - Ensure Tailscale is running on server

2. **SSH Connection Failed**
   - Verify SSH key is added to authorized_keys
   - Check user permissions
   - Test SSH connection manually

3. **Configuration Test Failed**
   - Check NixOS configuration syntax
   - Verify all required files are present
   - Check GitHub Actions logs for detailed error information

4. **Deployment Failed**
   - Check for conflicting services
   - Verify system resources
   - Use manual rollback by copying backup files

### Debug Commands

```bash
# Test SSH connection
ssh github-actions@your-server.ts.net

# Manual configuration test
sudo nixos-rebuild dry-run

# List available backups
ls -la /var/backups/nixos/

# Manual rollback
sudo cp -r /var/backups/nixos/config_20240101_120000/* /etc/nixos/
sudo nixos-rebuild switch
```

## Security Considerations

- **SSH Keys**: Use dedicated SSH keys for GitHub Actions
- **Sudo Permissions**: Limited sudo access for deployment user
- **Tailscale**: Secure network connection
- **Backups**: Automatic backup before deployment
- **Logging**: Comprehensive audit trail in GitHub Actions

## Customization

### Adding Custom Services

To add custom services to the deployment:

1. Add service files to your repository
2. Update the GitHub Actions workflows to copy additional files
3. Modify the deployment logic in the workflows if needed

### Custom Notifications

Add custom notification hooks to the GitHub Actions workflows:

```yaml
- name: Notify on success
  if: success()
  run: |
    curl -X POST "https://hooks.slack.com/your-webhook" \
         -H "Content-Type: application/json" \
         -d '{"text":"NixOS deployment successful!"}'
```

## Support

For issues and questions:

1. Check the troubleshooting section
2. Review GitHub Actions logs for detailed error information
3. Check Tailscale connectivity
4. Verify server permissions

## License

This configuration is part of your NixOS setup and follows your existing license terms.