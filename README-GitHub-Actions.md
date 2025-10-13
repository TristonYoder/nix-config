# NixOS GitHub Actions Integration

This repository includes automated testing and deployment of NixOS configurations using GitHub Actions and Tailscale.

## ⚡ Multi-Host Support

**NEW:** This setup now supports **multiple NixOS hosts** with parallel testing and deployment!

👉 **See [README-GitHub-Actions-MultiHost.md](README-GitHub-Actions-MultiHost.md) for complete multi-host documentation**

## Features

- ✅ **Multi-Host Deployment**: Deploy to multiple NixOS hosts in parallel
- ✅ **Parallel Testing**: Test all configurations simultaneously  
- ✅ **Selective Deployment**: Deploy to all or specific hosts manually
- ✅ **Automated Testing**: Test NixOS configurations on every push and pull request
- ✅ **Branch Testing**: Test all branches (main, develop, feature/*, bugfix/*)
- ✅ **Automatic Deployment**: Deploy to production when main branch tests pass
- ✅ **Rollback Support**: Automatic configuration backups with rollback capability
- ✅ **Tailscale Integration**: Secure connection to your server via Tailscale
- ✅ **Minimal Server Changes**: No need to overhaul your existing NixOS setup

## Architecture

### Single Host (Legacy)
```
GitHub Repository → GitHub Actions → Tailscale → Your NixOS Server
```

### Multi-Host (Current)
```
                                     ┌─→ david (main server)
                                     │
GitHub Repository → GitHub Actions → Tailscale → pits (edge VPS)
                                     │
                                     └─→ tristons-desk (desktop)
```

1. **GitHub Actions** triggers on code changes
2. **Tailscale** provides secure connection to all servers
3. **GitHub Actions** handles all deployment logic in parallel
4. **Backup System** ensures rollback capability on each host

📚 **For multi-host setup details, see [README-GitHub-Actions-MultiHost.md](README-GitHub-Actions-MultiHost.md)**

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

### Step 3: Add Public Key to NixOS Configuration

Add the **public key** to your NixOS configuration:

1. **Copy the public key content:**
   ```bash
   cat ~/.ssh/github_actions.pub
   ```

2. **Edit `github-actions.nix`** and uncomment/update the SSH key line:
   ```nix
   openssh.authorizedKeys.keys = [
     "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... github-actions@david-nixos"
   ];
   ```

3. **Apply the configuration:**
   ```bash
   sudo nixos-rebuild switch
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

### Step 5: Setup Tailscale ACL Policy

You need to configure your Tailscale ACL policy to allow SSH access from GitHub Actions:

1. Go to [Tailscale Admin Console](https://login.tailscale.com/admin/acls)
2. Edit your ACL policy file and add the following configuration:
   ```json
   {
     "tagOwners": {
       "tag:github-actions": ["your-email@example.com"]
     },
     "acls": [
       {
         "action": "accept",
         "src": ["tag:github-actions"],
         "dst": ["autogroup:members"]
       }
     ]
   }
   ```
3. Replace `your-email@example.com` with your actual Tailscale account email
4. Save the ACL policy

**What this does:**
- **Defines the tag** - `tag:github-actions` is now allowed
- **Allows SSH access** - GitHub Actions can connect to all members of your tailnet via SSH (port 22)
- **Sets ownership** - Your email can assign this tag

### Step 5.1: Configure SSH Access on Server

You also need to configure SSH access on your server to allow the `github-actions` user:

1. **SSH into your server:**
   ```bash
   ssh your-username@your-server.ts.net
   ```

2. **Configure Tailscale SSH access:**
   ```bash
   sudo tailscale ssh --config
   ```

3. **Add SSH configuration for github-actions user:**
   ```json
   {
     "action": "accept",
     "src": ["tag:github-actions"],
     "dst": ["autogroup:members"],
     "users": ["github-actions"]
   }
   ```

4. **Apply the SSH configuration:**
   ```bash
   sudo tailscale ssh --config > /etc/tailscale/ssh.json
   sudo systemctl restart tailscaled
   ```

**What this does:**
- **Allows SSH access** from `tag:github-actions` to any member
- **Restricts to specific user** - Only `github-actions` user can connect
- **Configures Tailscale SSH** to permit the connection

### Step 6: Setup Tailscale OAuth

1. Go to [Tailscale Admin Console](https://login.tailscale.com/admin/settings/oauth)
2. Click **Generate OAuth client**
3. Fill in:
   - **Client name**: `david-nixos-github-actions`
   - **Redirect URI**: `https://github.com/your-username/david-nixos`
4. Click **Generate**
5. Copy the **Client ID** and **Secret** to your GitHub repository secrets

### Step 7: Add SSH Private Key to GitHub

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

### Step 8: Test the Setup

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

4. **Sudo Password Required**
   - Ensure `sudo nixos-rebuild switch` has been run to apply the configuration
   - Verify the `github-actions` user exists: `id github-actions`
   - Check sudo permissions: `sudo -l -U github-actions`
   - If permissions are missing, run `sudo nixos-rebuild switch` again

5. **Deployment Failed**
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