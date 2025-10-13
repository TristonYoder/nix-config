# Multi-Host Deployment Quick Reference

## 🚀 Quick Start

Your GitHub Actions workflows now automatically test and deploy to **all NixOS hosts** when you push to the `main` branch.

### Configured Hosts

| Host | Type | Auto-Deploy |
|------|------|-------------|
| `david` | Main Server | ✅ Yes |
| `pits` | Edge VPS | ✅ Yes |
| `tristons-desk` | Desktop | ✅ Yes |

## 📋 Common Tasks

### Deploy to All Hosts

**Automatic (recommended):**
```bash
git checkout main
git pull
git add .
git commit -m "Update configurations"
git push origin main
```

**Manual:**
1. Go to GitHub → Actions
2. Select "Deploy NixOS Flake Configuration"
3. Click "Run workflow"
4. Enter `all` (or leave default)
5. Click "Run workflow"

### Deploy to Specific Hosts

**Manual workflow dispatch:**
1. Go to GitHub → Actions
2. Select "Deploy NixOS Flake Configuration"
3. Click "Run workflow"
4. Enter: `david,pits` (comma-separated, no spaces)
5. Click "Run workflow"

### Test Without Deploying

Push to any branch other than `main`:
```bash
git checkout -b feature/my-changes
git add .
git commit -m "Test new feature"
git push origin feature/my-changes
```

Tests run on all hosts, but no deployment happens.

## 🔄 Workflow Summary

### Test Workflow

**Runs on:** Every push and pull request

**Steps:**
1. ✅ Check flake syntax (fast fail)
2. ✅ Test `david` configuration
3. ✅ Test `pits` configuration  
4. ✅ Test `tristons-desk` configuration

All tests run **in parallel**.

### Deploy Workflow

**Runs on:** 
- Push to `main` (after successful tests)
- Manual trigger

**Steps for each host:**
1. 🔒 Create timestamped backup
2. ✅ Final dry-run test
3. 🚀 Deploy with `nixos-rebuild switch`

All deployments run **in parallel**.

## 🛠️ Migration Checklist

If upgrading from single-host setup:

- [ ] Updated workflows (already done ✅)
- [ ] Removed old `NIXOS_SERVER_HOSTNAME` secret (optional)
- [ ] Enabled `github-actions` module on all hosts
- [ ] Verified SSH keys work on all hosts
- [ ] All hosts connected to Tailscale
- [ ] Tested manual deployment to one host
- [ ] Monitored first automatic deployment
- [ ] Verified backups created on all hosts

## 🔑 Required GitHub Secrets

| Secret | Description | Still Needed? |
|--------|-------------|---------------|
| `TAILSCALE_OAUTH_CLIENT_ID` | Tailscale OAuth ID | ✅ Yes |
| `TAILSCALE_OAUTH_SECRET` | Tailscale OAuth Secret | ✅ Yes |
| `NIXOS_SERVER_USER` | SSH user (github-actions) | ✅ Yes |
| `SSH_PRIVATE_KEY` | SSH private key | ✅ Yes |
| `NIXOS_SERVER_HOSTNAME` | Server hostname | ❌ No (deprecated) |

## 📝 Adding/Removing Hosts

### Add a New Host

1. **Update test workflow** (`.github/workflows/test-nixos-config.yml`):
   ```yaml
   matrix:
     host: 
       - name: new-host
         hostname: new-host
   ```

2. **Update deploy workflow** (`.github/workflows/deploy-nixos-config.yml`):
   ```yaml
   ALL_HOSTS='["david", "pits", "tristons-desk", "new-host"]'
   ```

3. **Configure the host:**
   - Enable `modules.services.development.github-actions.enable = true`
   - Connect to Tailscale
   - Run `sudo nixos-rebuild switch`

### Remove a Host

**From testing and deployment:**
```yaml
# Remove from both workflow matrices
```

**From deployment only (keep testing):**
```yaml
# Keep in test workflow matrix
# Remove from deploy workflow ALL_HOSTS
```

## 🔍 Monitoring

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
✅ Each host backed up successfully  
✅ Services running on all hosts  

### Failure Indicators

❌ Any host shows red X  
⚠️ Deployment summary shows warning  
❌ Backup creation failed  
❌ Configuration test failed  

## 🆘 Rollback

### Quick Rollback (NixOS Generation)

```bash
ssh github-actions@hostname
sudo nixos-rebuild switch --rollback
```

### Backup Rollback

```bash
ssh github-actions@hostname

# List backups
ls -la /var/backups/nixos/

# Restore backup
sudo cp -r /var/backups/nixos/flake_config_TIMESTAMP/* /etc/nixos/
cd /etc/nixos
sudo nixos-rebuild switch --flake .#hostname
```

## 🎯 Best Practices

1. ✅ **Test on feature branches** before merging to main
2. ✅ **Use meaningful commit messages**
3. ✅ **Monitor first deployment** after changes
4. ✅ **Keep backups** (automatic, but verify)
5. ✅ **Review logs** after deployment
6. ✅ **Test rollback** procedure periodically
7. ✅ **Update workflows** when adding hosts
8. ✅ **Secure secrets** in GitHub settings

## 📖 Documentation

- **Complete Guide**: [README-GitHub-Actions-MultiHost.md](README-GitHub-Actions-MultiHost.md)
- **Original Setup**: [README-GitHub-Actions.md](README-GitHub-Actions.md)
- **General Info**: [README.md](README.md)

## 🐛 Troubleshooting

### Issue: Host unreachable

```bash
# Check Tailscale
sudo tailscale status

# Test SSH
ssh github-actions@hostname
```

### Issue: Configuration test fails

```bash
# SSH to host
ssh github-actions@hostname

# Manual test
cd /etc/nixos
sudo nixos-rebuild dry-run --flake .#hostname
```

### Issue: Deployment succeeds but service fails

```bash
# Check service status
systemctl status service-name

# View logs
journalctl -u service-name -f
```

### Issue: Some hosts succeed, others fail

This is **expected** with `fail-fast: false`:
1. Review failed host logs individually
2. Fix configuration for failed hosts
3. Manually re-deploy to failed hosts only

## 💡 Tips

- **Parallel = Faster**: All hosts update simultaneously
- **Independent Failures**: One host failure doesn't stop others
- **Selective Deployment**: Deploy to specific hosts manually
- **Backup Safety**: Each host backed up before deployment
- **Fast Feedback**: Syntax errors caught immediately

## 🔗 Related Files

- `.github/workflows/test-nixos-config.yml` - Test workflow
- `.github/workflows/deploy-nixos-config.yml` - Deploy workflow
- `modules/services/development/github-actions.nix` - GitHub Actions module
- `flake.nix` - NixOS configurations

## 📞 Need Help?

1. Check GitHub Actions logs
2. Review this quick reference
3. See complete documentation in [README-GitHub-Actions-MultiHost.md](README-GitHub-Actions-MultiHost.md)
4. Check system logs on affected hosts
5. Test manually on the host

---

**Last Updated**: January 2025  
**Managed Hosts**: 3 (david, pits, tristons-desk)  
**Deployment Type**: Parallel, Independent

