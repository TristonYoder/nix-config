# NixOS Configuration with Auto-Deployment

This repository contains my NixOS configuration with automated deployment using GitHub Actions and Tailscale.

## 🚀 Features

- **Automated Testing**: All branches and PRs are tested for configuration validity
- **Auto-Deployment**: Main branch changes are automatically deployed to the server
- **Tailscale Integration**: Secure connection to server via Tailscale
- **Rollback Support**: Automatic backups before each deployment
- **Status Flags**: GitHub status indicators for deployment results

## 📁 Structure

```
├── configuration.nix          # Main NixOS configuration
├── apps.nix                  # Non-docker applications
├── caddy-hosts.nix          # Caddy virtual hosts
├── server-deployment.nix     # Auto-deployment configuration
├── flake.nix                # Nix flake configuration
├── .github/workflows/       # GitHub Actions workflows
│   ├── test-configuration.yml
│   ├── deploy-to-server.yml
│   └── status-check.yml
└── docker/                   # Docker service configurations
```

## 🛠️ Setup

### Prerequisites

1. NixOS server with Tailscale installed
2. GitHub repository with your configuration
3. Tailscale OAuth credentials

### Quick Setup

1. **Clone and setup on your server:**
   ```bash
   git clone https://github.com/your-username/your-repo.git /tmp/nixos-config
   cd /tmp/nixos-config
   sudo ./setup-deployment.sh
   ```

2. **Configure GitHub Secrets:**
   - `TAILSCALE_OAUTH_CLIENT_ID`
   - `TAILSCALE_OAUTH_SECRET`
   - `SERVER_HOSTNAME`
   - `SERVER_USER`
   - `GITHUB_REPO_OWNER`
   - `GITHUB_REPO_NAME`

3. **Set up Tailscale OAuth:**
   - Go to [Tailscale Admin Console](https://login.tailscale.com/admin/settings/oauth)
   - Create OAuth client
   - Set redirect URI: `https://github.com/settings/connections/applications/oauth`

### Manual Setup

For detailed setup instructions, see [DEPLOYMENT_SETUP.md](DEPLOYMENT_SETUP.md).

## 🔄 Workflow

### Testing (All Branches)
- Validates Nix syntax with `nix flake check`
- Tests configuration build with `nixos-rebuild dry-run`
- Sets GitHub status flags
- Comments on PRs with results

### Deployment (Main Branch Only)
- Tests configuration locally first
- Connects to server via Tailscale
- Backs up current configuration
- Deploys new configuration
- Sets deployment status flags

## 🛡️ Security

- **SSH Keys**: Dedicated keys for GitHub Actions
- **Limited Permissions**: Deployment user has minimal sudo access
- **Encrypted Connection**: Tailscale provides secure networking
- **Automatic Backups**: Configurations are backed up before deployment

## 📊 Monitoring

### View Logs
```bash
# Deployment logs
sudo journalctl -u nixos-auto-deploy -f

# System logs
sudo journalctl -f

# Tailscale status
tailscale status
```

### Check Status
- GitHub Actions tab shows workflow results
- Status flags appear on commits and PRs
- Server logs contain detailed deployment information

## 🔧 Configuration

### Adding New Services

1. Create service configuration in appropriate file
2. Add to `configuration.nix` imports if needed
3. Test with `nixos-rebuild dry-run --flake .#david`
4. Commit and push to trigger deployment

### Custom Deployment

Modify `server-deployment.nix` for custom deployment behavior:

```nix
# Add pre-deployment hooks
ExecStartPre = pkgs.writeShellScript "pre-deploy" ''
  echo "Running pre-deployment checks..."
'';

# Add post-deployment hooks
ExecStartPost = pkgs.writeShellScript "post-deploy" ''
  echo "Running post-deployment tasks..."
'';
```

## 🚨 Troubleshooting

### Common Issues

1. **Tailscale Connection Fails**
   - Check OAuth credentials
   - Verify server hostname
   - Ensure Tailscale is running

2. **SSH Connection Fails**
   - Verify SSH key setup
   - Check user permissions
   - Test connection manually

3. **Deployment Fails**
   - Check server logs
   - Verify configuration validity
   - Test with dry-run locally

### Recovery

If deployment fails:

```bash
# List backups
ls -la /var/lib/nixos-backups/

# Restore from backup
sudo cp -r /var/lib/nixos-backups/nixos-backup-YYYYMMDD-HHMMSS /etc/nixos
sudo nixos-rebuild switch
```

## 📚 Documentation

- [DEPLOYMENT_SETUP.md](DEPLOYMENT_SETUP.md) - Detailed setup guide
- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [Tailscale Documentation](https://tailscale.com/kb/)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test with `nixos-rebuild dry-run --flake .#david`
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🙏 Acknowledgments

- [NixOS](https://nixos.org/) for the amazing operating system
- [Tailscale](https://tailscale.com/) for secure networking
- [GitHub Actions](https://github.com/features/actions) for CI/CD
