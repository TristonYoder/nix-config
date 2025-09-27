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

## Complete Setup Instructions

### Step 1: Apply NixOS Configuration

On your NixOS server, run:

```bash
# This creates the github-actions user and all necessary permissions
sudo nixos-rebuild switch
```

**What this does:**
- Creates `github-actions` user
- Sets up sudo permissions for deployment commands
- Creates backup directory `/var/backups/nixos`
- Installs required packages (rsync, dnsutils, git, bash)

### Step 2: Generate SSH Key Pair

On your **local machine** (not the server), generate an SSH key:

```bash
# Generate SSH key pair
ssh-keygen -t ed25519 -C "github-actions@david-nixos" -f ~/.ssh/github_actions

# This creates two files:
# ~/.ssh/github_actions (private key)
# ~/.ssh/github_actions.pub (public key)
```

### Step 3: Add Public Key to Server

Copy the **public key** to your server:

```bash
# Method 1: Use ssh-copy-id (recommended)
ssh-copy-id -i ~/.ssh/github_actions.pub github-actions@your-server.ts.net

# Method 2: Manual copy (if ssh-copy-id doesn't work)
# First, copy the public key content:
cat ~/.ssh/github_actions.pub

# Then SSH to your server and add it:
ssh your-username@your-server.ts.net
sudo su - github-actions
mkdir -p ~/.ssh
echo 'PASTE_THE_PUBLIC_KEY_HERE' >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
chmod 700 ~/.ssh
```

### Step 4: Configure GitHub Repository Secrets

In your GitHub repository (`david-nixos`), go to **Settings** → **Secrets and variables** → **Actions** and add these secrets:

| Secret Name | Description | How to Get |
|-------------|-------------|------------|
| `TAILSCALE_OAUTH_CLIENT_ID` | Tailscale OAuth Client ID | See Step 5 below |
| `TAILSCALE_OAUTH_SECRET` | Tailscale OAuth Secret | See Step 5 below |
| `NIXOS_SERVER_HOSTNAME` | Your server's Tailscale hostname | Your server's hostname (e.g., `david`) |
| `NIXOS_SERVER_USER` | SSH user for GitHub Actions | `github-actions` |
| `SSH_PRIVATE_KEY` | SSH private key content | See Step 6 below |

### Step 5: Setup Tailscale OAuth

1. Go to [Tailscale Admin Console](https://login.tailscale.com/admin/settings/oauth)
2. Click **Generate OAuth client**
3. Fill in:
   - **Client name**: `david-nixos-github-actions`
   - **Redirect URI**: `https://github.com/your-username/david-nixos`
4. Click **Generate**
5. Copy the **Client ID** and **Secret** to your GitHub repository secrets

### Step 6: Add SSH Private Key to GitHub

Copy your **private key** content to GitHub:

```bash
# Display the private key content
cat ~/.ssh/github_actions

# Copy the entire output (including -----BEGIN and -----END lines)
# Add it to GitHub repository secrets as SSH_PRIVATE_KEY
```

**Important:** The private key should look like this:
```
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
... (many more lines) ...
-----END OPENSSH PRIVATE KEY-----
```

### Step 7: Test the Setup

1. **Push a change** to your repository
2. **Check GitHub Actions** tab in your repository
3. **Look for** "Test NixOS Configuration" workflow
4. **Verify** it connects to your server and runs `nixos-rebuild dry-run`

## Workflow Details

### Test Workflow (`test-nixos-config.yml`)

**Triggers:**
- Push to any branch
- Pull requests to main

**What it does:**
1. Connects to server via Tailscale
2. Copies configuration files to `/tmp/nixos-config-test/`
3. Runs `nixos-rebuild dry-run`
4. Reports success/failure status

### Deploy Workflow (`deploy-nixos-config.yml`)

**Triggers:**
- Push to main branch (after successful tests)
- Manual trigger

**What it does:**
1. Creates backup in `/var/backups/nixos/config_YYYYMMDD_HHMMSS/`
2. Copies new configuration to `/etc/nixos/`
3. Runs final test with `nixos-rebuild dry-run`
4. Deploys with `nixos-rebuild switch`
5. Reports deployment status

## Backup System

The system automatically creates backups in `/var/backups/nixos/`:

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
- **Location**: `/var/backups/nixos/`
- **Format**: `config_YYYYMMDD_HHMMSS/`

## Manual Rollback

If deployment fails, you can manually rollback:

```bash
# SSH to your server
ssh your-username@your-server.ts.net

# List available backups
ls -la /var/backups/nixos/

# Copy backup files back to /etc/nixos/
sudo cp -r /var/backups/nixos/config_20240101_120000/* /etc/nixos/

# Apply the rollback
sudo nixos-rebuild switch
```

## Troubleshooting

### Common Issues

1. **Tailscale Connection Failed**
   - Check Tailscale OAuth credentials in GitHub secrets
   - Verify `NIXOS_SERVER_HOSTNAME` is correct (e.g., `david`)
   - Ensure Tailscale is running on server

2. **SSH Connection Failed**
   - Verify SSH key is added to `/home/github-actions/.ssh/authorized_keys`
   - Check file permissions: `chmod 600 ~/.ssh/authorized_keys`
   - Test SSH connection: `ssh github-actions@your-server.ts.net`

3. **Configuration Test Failed**
   - Check NixOS configuration syntax
   - Verify all required files are present
   - Check GitHub Actions logs for detailed error information

4. **Deployment Failed**
   - Check for conflicting services
   - Verify system resources
   - Use manual rollback (see above)

### Debug Commands

```bash
# Test SSH connection
ssh github-actions@your-server.ts.net

# Manual configuration test
sudo nixos-rebuild dry-run

# List available backups
ls -la /var/backups/nixos/

# Check GitHub Actions logs
# Go to your repository → Actions tab → Click on failed workflow
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