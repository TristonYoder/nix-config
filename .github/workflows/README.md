# GitHub Actions CI/CD

Automated testing and deployment for all NixOS hosts using GitHub Actions.

## Overview

This repository uses GitHub Actions to automatically test and deploy NixOS configurations to multiple hosts in parallel. When you push to the `main` branch, the workflows will:

1. ✅ Validate flake syntax
2. ✅ Test all NixOS configurations in parallel
3. ✅ Deploy to all hosts automatically if tests pass

## Architecture

```
Push to main
    ↓
Syntax Check (30s)
    ↓
┌─────────────┬─────────────┬─────────────┐
│   david     │    pits     │ tristons-   │
│   TEST      │    TEST     │  desk TEST  │
│  (2-3 min)  │  (2-3 min)  │  (2-3 min)  │
└─────────────┴─────────────┴─────────────┘
    ↓ All Pass
┌─────────────┬─────────────┬─────────────┐
│   david     │    pits     │ tristons-   │
│   DEPLOY    │   DEPLOY    │ desk DEPLOY │
│  (3-5 min)  │  (3-5 min)  │  (3-5 min)  │
└─────────────┴─────────────┴─────────────┘
```

## Managed Hosts

| Host | Type | Auto-Deploy |
|------|------|-------------|
| **david** | Main Server | ✅ Yes |
| **pits** | Edge VPS | ✅ Yes |
| **tristons-desk** | Desktop | ✅ Yes |

## Workflows

### Test Workflow

**Triggers:** Every push and pull request

**Steps:**
1. Check flake syntax locally (fast fail)
2. Connect to Tailscale network
3. Test all hosts in parallel:
   - `david` (main server)
   - `pits` (edge VPS)  
   - `tristons-desk` (desktop)
4. Run `nixos-rebuild dry-run` on each
5. Report independent results

**Features:**
- Parallel execution
- Fast syntax check
- Independent failures (one host failing doesn't stop others)

### Deploy Workflow

**Triggers:**
- Automatic after successful test on `main` branch
- Manual trigger with host selection

**Steps for each host:**
1. Create timestamped backup
2. Run final dry-run test
3. Deploy with `nixos-rebuild switch`
4. Report success/failure

**Features:**
- Parallel deployment
- Selective deployment (manual)
- Automatic backups
- Independent failures

## Usage

### Automatic Deployment

Push to the `main` branch:

```bash
git checkout main
git add .
git commit -m "Update configurations"
git push origin main
```

This automatically:
1. Tests all hosts
2. Deploys to all hosts if tests pass

### Manual Deployment

Deploy to all hosts:
1. GitHub → Actions
2. "Deploy NixOS Flake Configuration"
3. "Run workflow"
4. Hosts: `all` (default)
5. "Run workflow"

Deploy to specific hosts:
1. GitHub → Actions  
2. "Deploy NixOS Flake Configuration"
3. "Run workflow"
4. Hosts: `david,pits` (comma-separated)
5. "Run workflow"

### Test Without Deploying

Push to any branch except `main`:

```bash
git checkout -b feature/new-feature
git add .
git commit -m "Test new feature"
git push origin feature/new-feature
```

Tests run, but no deployment occurs.

## Required GitHub Secrets

Configure these in your repository settings:

| Secret | Description |
|--------|-------------|
| `TAILSCALE_OAUTH_CLIENT_ID` | Tailscale OAuth Client ID |
| `TAILSCALE_OAUTH_SECRET` | Tailscale OAuth Secret |
| `NIXOS_SERVER_USER` | SSH user (github-actions) |
| `SSH_PRIVATE_KEY` | SSH private key for all hosts |

### Setting Up Secrets

1. **Tailscale OAuth:**
   - Go to https://login.tailscale.com/admin/settings/oauth
   - Create a new OAuth client
   - Tag: `tag:github-actions`
   - Copy Client ID and Secret to GitHub secrets

2. **SSH Key:**
   - Generate a dedicated SSH key: `ssh-keygen -t ed25519 -C "github-actions@david-nixos"`
   - Add public key to each host's configuration
   - Add private key to GitHub secrets

3. **GitHub Repository:**
   - Settings → Secrets and variables → Actions
   - Add each secret

## Host Configuration

Each host needs:

### 1. Enable GitHub Actions Module

In host configuration or profile:

```nix
{
  modules.services.development.github-actions.enable = true;
}
```

### 2. Connect to Tailscale

```bash
# On each host
sudo tailscale status  # Verify connected
```

### 3. Apply Configuration

```bash
# On each host
sudo nixos-rebuild switch --flake .
```

This creates the `github-actions` user and authorizes the SSH key.

## Tailscale ACL Configuration

Add to your Tailscale ACL policy:

```json
{
  "tagOwners": {
    "tag:github-actions": ["your-email@example.com"]
  },
  "acls": [
    {
      "action": "accept",
      "src": ["tag:github-actions"],
      "dst": ["autogroup:members:*"]
    }
  ]
}
```

## Adding a New Host

1. **Create host configuration** in `flake.nix`
2. **Add to test workflow** (`.github/workflows/test-nixos-config.yml`):
   ```yaml
   matrix:
     host: 
       - name: new-host
         hostname: new-host
   ```
3. **Add to deploy workflow** (`.github/workflows/deploy-nixos-config.yml`):
   ```yaml
   ALL_HOSTS='["david", "pits", "tristons-desk", "new-host"]'
   ```
4. **Configure the host:**
   - Enable `modules.services.development.github-actions.enable = true`
   - Connect to Tailscale
   - Apply configuration

## Monitoring

### View Status

**GitHub Actions Tab:**
- See all workflow runs
- View parallel job execution
- Check individual host logs

**Individual Host:**
```bash
ssh github-actions@hostname
journalctl -xe
sudo nixos-rebuild list-generations
```

### Success Indicators

✅ All hosts show green checkmarks  
✅ Deployment summary shows success  
✅ Backups created successfully  
✅ Services running on all hosts  

## Rollback

### NixOS Generation Rollback

```bash
ssh github-actions@hostname
sudo nixos-rebuild switch --rollback
```

### Configuration Backup Rollback

```bash
ssh github-actions@hostname

# List backups
ls -la /var/backups/nixos/

# Restore from backup
sudo cp -r /var/backups/nixos/flake_config_TIMESTAMP/* /etc/nixos/
cd /etc/nixos
sudo nixos-rebuild switch --flake .#hostname
```

## Troubleshooting

### Host Unreachable

```bash
# Check Tailscale
sudo tailscale status

# Test SSH
ssh github-actions@hostname
```

### Configuration Test Fails

```bash
# SSH to host
ssh github-actions@hostname

# Manual test
cd /etc/nixos
sudo nixos-rebuild dry-run --flake .#hostname
```

### Some Hosts Fail, Others Succeed

This is expected with `fail-fast: false`:
1. Review failed host logs individually
2. Fix configuration for failed hosts
3. Manually re-deploy to failed hosts only

## Security Considerations

### SSH Keys
- Use dedicated SSH keys for GitHub Actions
- Store private keys securely in GitHub Secrets
- Rotate keys periodically

### Sudo Permissions
- GitHub Actions user has full sudo access (required for nixos-rebuild)
- Audit sudo usage in logs

### Tailscale ACLs
- Restrict `tag:github-actions` to necessary hosts
- Regularly review ACL policies

### Backups
- Automatic backups before each deployment
- Maintain at least 10 generations
- Test restore procedures regularly

## Best Practices

1. ✅ **Test on feature branches** before merging to main
2. ✅ **Use meaningful commit messages** for audit trail
3. ✅ **Monitor first deployment** after changes
4. ✅ **Keep backups** for quick rollback
5. ✅ **Review logs** after deployment
6. ✅ **Test rollback** procedure periodically
7. ✅ **Update workflows** when adding/removing hosts
8. ✅ **Secure your secrets** and rotate regularly

## Performance

### Parallel vs Sequential

**Before (sequential):**
- Test 3 hosts: ~9 minutes
- Deploy 3 hosts: ~15 minutes
- Total: ~24 minutes

**After (parallel):**
- Test 3 hosts: ~3 minutes
- Deploy 3 hosts: ~5 minutes  
- Total: ~8 minutes

**Improvement:** 66% faster! ⚡

## Resources

- [Test Workflow](.github/workflows/test-nixos-config.yml)
- [Deploy Workflow](.github/workflows/deploy-nixos-config.yml)
- [GitHub Actions Module](../modules/services/development/github-actions.nix)
- [Tailscale Documentation](https://tailscale.com/kb/)

---

**Last Updated:** October 13, 2025  
**Status:** Active  
**Managed Hosts:** 3 (david, pits, tristons-desk)

