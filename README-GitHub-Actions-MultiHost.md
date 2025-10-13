# Multi-Host GitHub Actions Deployment

This guide explains how to use the updated GitHub Actions workflows to automatically test and deploy your NixOS configurations to multiple hosts.

## Overview

The GitHub Actions setup now supports:

- ✅ **Parallel Testing**: Test all NixOS hosts simultaneously
- ✅ **Multi-Host Deployment**: Deploy to all or selected hosts after successful tests
- ✅ **Manual Deployment**: Trigger deployments manually with host selection
- ✅ **Fail-Safe**: Continue testing/deploying other hosts even if one fails
- ✅ **Fast Feedback**: Flake syntax check runs first for quick failure detection

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     GitHub Repository                        │
│                    (Push to any branch)                      │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│              Test Workflow (Parallel)                        │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │    david     │  │     pits     │  │ tristons-desk│      │
│  │   (server)   │  │  (edge VPS)  │  │  (desktop)   │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼ (Only on main branch)
┌─────────────────────────────────────────────────────────────┐
│           Deploy Workflow (Parallel)                         │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │    david     │  │     pits     │  │ tristons-desk│      │
│  │   DEPLOY     │  │   DEPLOY     │  │   DEPLOY     │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
└─────────────────────────────────────────────────────────────┘
```

## Workflows

### 1. Test Workflow (`test-nixos-config.yml`)

**Triggers:**
- Push to any branch
- Pull requests to main

**What it does:**
1. Checks flake syntax locally (fast fail)
2. Tests all NixOS configurations in parallel:
   - `david` (main server)
   - `pits` (edge VPS)
   - `tristons-desk` (desktop)
3. Runs `nixos-rebuild dry-run` on each host
4. Reports success/failure for each host independently

**Features:**
- **Parallel execution**: All hosts tested simultaneously
- **Non-blocking**: One host failure doesn't stop others
- **Fast feedback**: Syntax errors caught immediately

### 2. Deploy Workflow (`deploy-nixos-config.yml`)

**Triggers:**
- Automatically after successful test on `main` branch
- Manual trigger with host selection (workflow_dispatch)

**What it does:**
1. Determines which hosts to deploy (all or selected)
2. Deploys to all specified hosts in parallel:
   - Creates timestamped backup
   - Runs final `dry-run` test
   - Deploys with `nixos-rebuild switch`
3. Reports overall deployment status

**Features:**
- **Selective deployment**: Deploy to specific hosts manually
- **Parallel deployment**: All hosts updated simultaneously
- **Backup safety**: Each host backed up before deployment
- **Independent failures**: One host failure doesn't affect others

## Usage Examples

### Automatic Deployment (Main Branch)

When you push to the `main` branch:

```bash
git checkout main
git add .
git commit -m "Update NixOS configurations"
git push origin main
```

**What happens:**
1. Test workflow runs on all hosts
2. If all tests pass, deploy workflow automatically deploys to all hosts
3. You get notifications for each step

### Manual Deployment (Any Branch)

Deploy to all hosts manually:

1. Go to GitHub Actions tab
2. Select "Deploy NixOS Flake Configuration"
3. Click "Run workflow"
4. Enter `all` in the hosts field (or leave default)
5. Click "Run workflow"

Deploy to specific hosts only:

1. Go to GitHub Actions tab
2. Select "Deploy NixOS Flake Configuration"
3. Click "Run workflow"
4. Enter comma-separated hosts: `david,pits`
5. Click "Run workflow"

### Testing Without Deployment

Test configurations on any branch:

```bash
git checkout develop
git add .
git commit -m "Test new configuration"
git push origin develop
```

**What happens:**
1. Test workflow runs on all hosts
2. No deployment occurs (not on main branch)
3. You see test results for all hosts

## Configuration

### Managed Hosts

The workflows are configured to manage these NixOS hosts:

```yaml
hosts:
  - david          # Main server
  - pits           # Edge VPS (Pi in the Sky)
  - tristons-desk  # Desktop workstation
```

**Note:** `tyoder-mbp` (macOS/Darwin) is not included as it requires different deployment mechanisms.

### Adding a New Host

To add a new NixOS host to the automation:

1. **Update test workflow** (`.github/workflows/test-nixos-config.yml`):
   ```yaml
   matrix:
     host: 
       - name: david
         hostname: david
       - name: pits
         hostname: pits
       - name: tristons-desk
         hostname: tristons-desk
       - name: new-host        # Add this
         hostname: new-host    # Add this
   ```

2. **Update deploy workflow** (`.github/workflows/deploy-nixos-config.yml`):
   ```yaml
   ALL_HOSTS='["david", "pits", "tristons-desk", "new-host"]'
   ```

3. **Ensure the new host has:**
   - GitHub Actions user configured (see Setup section below)
   - SSH key authorized
   - Tailscale connected
   - Proper hostname resolution

### Removing a Host from Automation

To exclude a host from automatic deployments (e.g., desktop workstation):

**Option 1: Remove from both workflows**
- Remove from test and deploy workflow matrices

**Option 2: Keep testing, skip deployment**
- Keep in test workflow
- Remove from deploy workflow's `ALL_HOSTS`

**Example:** Keep `tristons-desk` for testing only:

```yaml
# In test-nixos-config.yml - KEEP
matrix:
  host: 
    - name: tristons-desk
      hostname: tristons-desk

# In deploy-nixos-config.yml - REMOVE
ALL_HOSTS='["david", "pits"]'  # tristons-desk removed
```

## Required GitHub Secrets

Ensure these secrets are configured in your repository:

| Secret Name | Description | Example |
|-------------|-------------|---------|
| `TAILSCALE_OAUTH_CLIENT_ID` | Tailscale OAuth Client ID | `k123...` |
| `TAILSCALE_OAUTH_SECRET` | Tailscale OAuth Secret | `tskey-...` |
| `NIXOS_SERVER_USER` | SSH user for deployments | `github-actions` |
| `SSH_PRIVATE_KEY` | SSH private key for all hosts | `-----BEGIN OPENSSH PRIVATE KEY-----...` |

**Note:** The old `NIXOS_SERVER_HOSTNAME` secret is no longer needed as hostnames are now defined in the workflow matrices.

## Setup for Each Host

Each NixOS host needs to be configured to accept GitHub Actions deployments:

### 1. Enable GitHub Actions Module

In the host's configuration (e.g., `hosts/pits/configuration.nix`):

```nix
{
  # Enable GitHub Actions integration
  modules.services.development.github-actions.enable = true;
}
```

Or in the profile (e.g., `profiles/server.nix`, `profiles/edge.nix`):

```nix
{
  # Enable for all servers
  modules.services.development.github-actions.enable = true;
}
```

### 2. Configure SSH Key

The SSH key in GitHub secrets must be authorized on all hosts. The `github-actions.nix` module handles this automatically, but you can customize it:

```nix
{
  modules.services.development.github-actions = {
    enable = true;
    sshKey = "ssh-ed25519 AAAAC3Nza... github-actions@david-nixos";
  };
}
```

### 3. Ensure Tailscale is Running

Each host must be connected to your Tailscale network:

```bash
# On each host
sudo tailscale status
```

### 4. Apply Configuration

On each host:

```bash
sudo nixos-rebuild switch
```

## Monitoring and Debugging

### View Workflow Status

1. Go to your repository on GitHub
2. Click the "Actions" tab
3. Select a workflow run to see detailed logs

### Check Individual Host Results

Each host's test and deployment runs independently. You can:

1. View the matrix job results
2. Expand specific host logs
3. See which hosts passed/failed

### Common Issues

**Issue: Host not reachable via Tailscale**
```
Solution: 
- Verify Tailscale is running on the host
- Check Tailscale ACL allows tag:github-actions
- Confirm hostname matches Tailscale device name
```

**Issue: SSH authentication failed**
```
Solution:
- Verify SSH_PRIVATE_KEY secret is correct
- Check github-actions user exists on host
- Ensure SSH key is authorized in github-actions.nix
```

**Issue: Configuration test passed but deployment failed**
```
Solution:
- Check for stateful issues (running services, file locks)
- Review deployment logs for specific errors
- SSH to host and manually run: sudo nixos-rebuild switch --flake .#hostname
```

**Issue: Some hosts succeed, others fail**
```
This is expected behavior with fail-fast: false
- Review individual host logs
- Fix failing host configurations
- Manually re-run deployment for failed hosts only
```

## Rollback Procedure

If a deployment fails or causes issues:

### Automatic Rollback (NixOS Built-in)

Each host maintains NixOS generations:

```bash
# SSH to the affected host
ssh github-actions@hostname

# List available generations
sudo nixos-rebuild list-generations

# Rollback to previous generation
sudo nixos-rebuild switch --rollback
```

### Configuration Backup Rollback

The workflow creates timestamped backups:

```bash
# SSH to the affected host
ssh github-actions@hostname

# List backups
ls -la /var/backups/nixos/

# Restore from backup
sudo cp -r /var/backups/nixos/flake_config_20250113_120000/* /etc/nixos/
cd /etc/nixos
sudo nixos-rebuild switch --flake .#hostname
```

## Performance Considerations

### Parallel vs Sequential

The workflows use parallel execution by default:

**Advantages:**
- Faster overall deployment time
- Independent host failures
- Better resource utilization

**Disadvantages:**
- Higher concurrent load on GitHub Actions
- Multiple simultaneous SSH connections

### Optimizing Deployment Speed

1. **Reduce Tailscale wait time** if connections are fast:
   ```yaml
   - name: Wait for Tailscale connection
     run: sleep 5  # Reduced from 10
   ```

2. **Use Cachix** for Nix builds (add to workflow):
   ```yaml
   - name: Setup Cachix
     uses: cachix/cachix-action@v14
     with:
       name: your-cache
       authToken: '${{ secrets.CACHIX_AUTH_TOKEN }}'
   ```

3. **Binary cache** on local network for faster builds

## Security Considerations

### SSH Keys
- Use dedicated SSH keys for GitHub Actions (not personal keys)
- Store private keys securely in GitHub Secrets
- Rotate keys periodically
- Consider using different keys per host for isolation

### Sudo Permissions
- GitHub Actions user has full sudo access (required for nixos-rebuild)
- Limit to specific commands if possible
- Audit sudo usage in logs

### Tailscale ACLs
- Restrict `tag:github-actions` to necessary hosts
- Use Tailscale SSH for additional security
- Regularly review ACL policies

### Backups
- Backups are stored locally on each host
- Consider off-host backup strategy
- Maintain at least 10 generations
- Test restore procedures regularly

## Advanced Usage

### Conditional Deployment

Deploy only to production servers:

```yaml
# Modify deploy workflow
ALL_HOSTS='["david", "pits"]'  # Exclude desktop
```

### Staged Deployment

Deploy to staging first, then production:

1. Create separate workflows for staging/production
2. Manual approval step for production
3. Deploy to test host first, then others

### Custom Deployment Order

Deploy to hosts sequentially instead of parallel:

```yaml
# In deploy workflow, remove matrix strategy
# Add multiple jobs instead:
jobs:
  deploy-david:
    # ... deploy david
  
  deploy-pits:
    needs: deploy-david
    # ... deploy pits
```

### Host-Specific Secrets

Use different secrets for different hosts:

```yaml
# In workflow
- name: Get host-specific secret
  run: |
    case "${{ matrix.host }}" in
      david)
        SECRET="${{ secrets.DAVID_SPECIFIC_SECRET }}"
        ;;
      pits)
        SECRET="${{ secrets.PITS_SPECIFIC_SECRET }}"
        ;;
    esac
```

## Migration from Single-Host Setup

If you're upgrading from the old single-host workflow:

1. **Update workflows** with new multi-host versions (already done)
2. **Update secrets**:
   - Old `NIXOS_SERVER_HOSTNAME` no longer needed
   - Ensure `SSH_PRIVATE_KEY` works for all hosts
3. **Enable github-actions module** on all hosts
4. **Test manually** before automatic deployment:
   ```bash
   # Manual workflow dispatch
   # Deploy to one host first
   ```
5. **Monitor first deployment** closely
6. **Verify backups** were created on all hosts

## Best Practices

1. **Test on feature branches** before merging to main
2. **Use meaningful commit messages** for audit trail
3. **Monitor workflow runs** regularly
4. **Review deployment logs** after each deployment
5. **Keep backups** for quick rollback
6. **Document host-specific configurations** 
7. **Test rollback procedures** periodically
8. **Update workflows** when adding/removing hosts
9. **Secure your secrets** and rotate regularly
10. **Use pull requests** for configuration changes

## Troubleshooting Checklist

Before deployment:
- [ ] All hosts reachable via Tailscale
- [ ] SSH keys authorized on all hosts
- [ ] GitHub secrets configured correctly
- [ ] github-actions module enabled on all hosts
- [ ] Configurations tested in flake check

After deployment:
- [ ] All hosts deployed successfully
- [ ] Services running correctly
- [ ] Backups created
- [ ] No errors in system logs
- [ ] Can SSH to all hosts

## Getting Help

If you encounter issues:

1. Check GitHub Actions logs for detailed error messages
2. SSH to the affected host and check system logs: `journalctl -xe`
3. Review this documentation
4. Check the main README-GitHub-Actions.md for general setup
5. Test manually on the host: `sudo nixos-rebuild switch --flake .#hostname`

## License

This configuration is part of your NixOS setup and follows your existing license terms.

