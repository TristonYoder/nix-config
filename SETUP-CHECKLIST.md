# Multi-Host GitHub Actions Setup Checklist

Use this checklist to ensure your multi-host GitHub Actions deployment is properly configured.

## ✅ Pre-Deployment Checklist

### GitHub Repository Setup

- [ ] **Workflows Updated**
  - [ ] `.github/workflows/test-nixos-config.yml` has matrix for all hosts
  - [ ] `.github/workflows/deploy-nixos-config.yml` has matrix for all hosts
  - [ ] Workflows committed to repository

- [ ] **GitHub Secrets Configured**
  - [ ] `TAILSCALE_OAUTH_CLIENT_ID` is set
  - [ ] `TAILSCALE_OAUTH_SECRET` is set
  - [ ] `NIXOS_SERVER_USER` is set (should be `github-actions`)
  - [ ] `SSH_PRIVATE_KEY` is set (complete private key)
  - [ ] ~~`NIXOS_SERVER_HOSTNAME`~~ (deprecated, can be removed)

### Tailscale Setup

- [ ] **Tailscale ACL Configured**
  - [ ] `tag:github-actions` defined in tagOwners
  - [ ] ACL allows `tag:github-actions` → `autogroup:members`
  - [ ] Your email set as tag owner

- [ ] **Tailscale OAuth Created**
  - [ ] OAuth client created at https://login.tailscale.com/admin/settings/oauth
  - [ ] Client ID matches GitHub secret
  - [ ] Secret matches GitHub secret

### Host Configuration

#### For `david` (Main Server)

- [ ] **System Configuration**
  - [ ] `modules.services.development.github-actions.enable = true`
  - [ ] Configuration applied: `sudo nixos-rebuild switch`
  - [ ] Host is on Tailscale network
  - [ ] Hostname is `david`: `hostname` command

- [ ] **GitHub Actions User**
  - [ ] User exists: `id github-actions`
  - [ ] Has sudo permissions: `sudo -l -U github-actions`
  - [ ] SSH key authorized: `sudo cat /home/github-actions/.ssh/authorized_keys`
  - [ ] Can SSH from GitHub Actions

- [ ] **Required Packages**
  - [ ] `rsync` installed
  - [ ] `git` installed
  - [ ] `bash` installed

- [ ] **Directories**
  - [ ] `/var/backups/nixos` exists
  - [ ] Backup directory writable

#### For `pits` (Edge Server)

- [ ] **System Configuration**
  - [ ] `modules.services.development.github-actions.enable = true`
  - [ ] Configuration applied: `sudo nixos-rebuild switch`
  - [ ] Host is on Tailscale network
  - [ ] Hostname is `pits`: `hostname` command

- [ ] **GitHub Actions User**
  - [ ] User exists: `id github-actions`
  - [ ] Has sudo permissions: `sudo -l -U github-actions`
  - [ ] SSH key authorized: `sudo cat /home/github-actions/.ssh/authorized_keys`
  - [ ] Can SSH from GitHub Actions

- [ ] **Required Packages**
  - [ ] `rsync` installed
  - [ ] `git` installed
  - [ ] `bash` installed

- [ ] **Directories**
  - [ ] `/var/backups/nixos` exists
  - [ ] Backup directory writable

#### For `tristons-desk` (Desktop)

- [ ] **System Configuration**
  - [ ] `modules.services.development.github-actions.enable = true`
  - [ ] Configuration applied: `sudo nixos-rebuild switch`
  - [ ] Host is on Tailscale network
  - [ ] Hostname is `tristons-desk`: `hostname` command

- [ ] **GitHub Actions User**
  - [ ] User exists: `id github-actions`
  - [ ] Has sudo permissions: `sudo -l -U github-actions`
  - [ ] SSH key authorized: `sudo cat /home/github-actions/.ssh/authorized_keys`
  - [ ] Can SSH from GitHub Actions

- [ ] **Required Packages**
  - [ ] `rsync` installed
  - [ ] `git` installed
  - [ ] `bash` installed

- [ ] **Directories**
  - [ ] `/var/backups/nixos` exists
  - [ ] Backup directory writable

### Connectivity Tests

- [ ] **From Local Machine**
  - [ ] Can ping all hosts via Tailscale
  - [ ] Can SSH to all hosts as github-actions user
  - [ ] All hosts show in `tailscale status`

- [ ] **From GitHub Actions** (test with manual workflow)
  - [ ] Tailscale connection succeeds
  - [ ] SSH connection succeeds for all hosts
  - [ ] Can rsync files to all hosts
  - [ ] Can run commands on all hosts

## ✅ Testing Checklist

### Initial Test (Feature Branch)

- [ ] **Create Test Branch**
  ```bash
  git checkout -b test/multi-host-deployment
  git add .
  git commit -m "Test multi-host deployment"
  git push origin test/multi-host-deployment
  ```

- [ ] **Verify Test Workflow**
  - [ ] Flake syntax check passes
  - [ ] `david` test passes
  - [ ] `pits` test passes
  - [ ] `tristons-desk` test passes
  - [ ] All tests complete successfully

### Manual Deployment Test (Single Host)

- [ ] **Trigger Manual Deployment**
  - [ ] Go to GitHub → Actions
  - [ ] Select "Deploy NixOS Flake Configuration"
  - [ ] Click "Run workflow"
  - [ ] Enter `david` in hosts field
  - [ ] Click "Run workflow"

- [ ] **Verify Single Host Deployment**
  - [ ] Deployment workflow starts
  - [ ] Tailscale connection succeeds
  - [ ] Backup created on `david`
  - [ ] Dry-run test passes
  - [ ] Deployment completes successfully
  - [ ] Services running on `david`

### Full Deployment Test (All Hosts)

- [ ] **Merge to Main**
  ```bash
  git checkout main
  git merge test/multi-host-deployment
  git push origin main
  ```

- [ ] **Verify Full Deployment**
  - [ ] Test workflow runs for all hosts
  - [ ] All tests pass
  - [ ] Deploy workflow starts automatically
  - [ ] All hosts deploy in parallel
  - [ ] All deployments complete successfully

- [ ] **Post-Deployment Verification**
  - [ ] All hosts accessible
  - [ ] Services running on all hosts
  - [ ] Backups created on all hosts
  - [ ] No errors in system logs

## ✅ Post-Deployment Checklist

### Verify Deployments

#### On `david`

- [ ] **System Status**
  ```bash
  ssh github-actions@david
  systemctl status
  nixos-version
  ```

- [ ] **Services Running**
  - [ ] Core services operational
  - [ ] No failed units: `systemctl --failed`

- [ ] **Backup Verification**
  ```bash
  ls -la /var/backups/nixos/
  # Should see timestamped backup directories
  ```

#### On `pits`

- [ ] **System Status**
  ```bash
  ssh github-actions@pits
  systemctl status
  nixos-version
  ```

- [ ] **Services Running**
  - [ ] Caddy running: `systemctl status caddy`
  - [ ] Tailscale running: `systemctl status tailscaled`

- [ ] **Backup Verification**
  ```bash
  ls -la /var/backups/nixos/
  ```

#### On `tristons-desk`

- [ ] **System Status**
  ```bash
  ssh github-actions@tristons-desk
  systemctl status
  nixos-version
  ```

- [ ] **Services Running**
  - [ ] Desktop environment working
  - [ ] No failed units

- [ ] **Backup Verification**
  ```bash
  ls -la /var/backups/nixos/
  ```

### Rollback Test

- [ ] **Test Rollback on One Host**
  ```bash
  ssh github-actions@david
  sudo nixos-rebuild switch --rollback
  ```

- [ ] **Verify Rollback**
  - [ ] System rolls back to previous generation
  - [ ] Services still running
  - [ ] Can roll forward again

- [ ] **Test Backup Restore**
  ```bash
  # List backups
  ls -la /var/backups/nixos/
  
  # Test restoring (don't actually apply)
  sudo cp -r /var/backups/nixos/flake_config_TIMESTAMP/* /tmp/restore-test/
  ```

## ✅ Monitoring Setup

### GitHub Actions

- [ ] **Enable Notifications**
  - [ ] Email notifications for failed workflows
  - [ ] Slack/Discord webhook (optional)

- [ ] **Review Settings**
  - [ ] Workflow permissions configured
  - [ ] Secrets properly secured
  - [ ] Branch protection rules (optional)

### Documentation

- [ ] **Update Local Docs**
  - [ ] README.md reviewed
  - [ ] Multi-host docs reviewed
  - [ ] Team informed of new process

- [ ] **Create Runbook**
  - [ ] Deployment procedures documented
  - [ ] Rollback procedures documented
  - [ ] Troubleshooting steps documented

## ✅ Maintenance Checklist (Ongoing)

### Weekly

- [ ] Review GitHub Actions workflow runs
- [ ] Check for failed deployments
- [ ] Review system logs on all hosts

### Monthly

- [ ] Test rollback procedure
- [ ] Verify backups are being created
- [ ] Review and clean old backups (automatic, but verify)
- [ ] Check Tailscale connectivity
- [ ] Rotate SSH keys (if policy requires)

### When Adding a New Host

- [ ] Add to flake.nix
- [ ] Add to test workflow matrix
- [ ] Add to deploy workflow ALL_HOSTS
- [ ] Configure github-actions module
- [ ] Connect to Tailscale
- [ ] Test deployment to new host only
- [ ] Update this checklist

## 🚨 Troubleshooting

### If Test Fails

1. [ ] Check GitHub Actions logs for specific error
2. [ ] SSH to failing host and test manually
3. [ ] Review configuration changes
4. [ ] Test locally: `nix flake check`
5. [ ] Fix configuration and push again

### If Deployment Fails

1. [ ] Check which host failed
2. [ ] Review deployment logs
3. [ ] SSH to host and check system logs
4. [ ] Rollback if necessary
5. [ ] Fix configuration
6. [ ] Deploy to failed host only

### If SSH Fails

1. [ ] Verify Tailscale connection: `tailscale status`
2. [ ] Check SSH key in GitHub secrets
3. [ ] Verify authorized_keys on host
4. [ ] Test SSH manually with same key
5. [ ] Re-apply configuration on host

## 📊 Success Criteria

Your multi-host deployment is successful when:

- ✅ All hosts show in Tailscale network
- ✅ All hosts pass tests automatically
- ✅ All hosts deploy successfully in parallel
- ✅ Backups created on all hosts
- ✅ Services running on all hosts
- ✅ Rollback works on all hosts
- ✅ No manual intervention needed
- ✅ Deployment time reduced (parallel)
- ✅ Team can deploy with confidence

## 📚 Resources

- [README-GitHub-Actions-MultiHost.md](README-GitHub-Actions-MultiHost.md) - Complete guide
- [MULTI-HOST-DEPLOYMENT.md](MULTI-HOST-DEPLOYMENT.md) - Quick reference
- [MULTI-HOST-GITHUB-ACTIONS-UPGRADE.md](MULTI-HOST-GITHUB-ACTIONS-UPGRADE.md) - Upgrade summary
- [README-GitHub-Actions.md](README-GitHub-Actions.md) - Original setup

## ✅ Final Verification

Once you've completed all checklists:

- [ ] All pre-deployment checks complete
- [ ] All testing checks complete
- [ ] All post-deployment checks complete
- [ ] Rollback tested and working
- [ ] Documentation reviewed
- [ ] Team informed and trained
- [ ] Monitoring in place
- [ ] Ready for production use

**Congratulations! Your multi-host GitHub Actions deployment is ready! 🎉**

---

**Last Updated**: January 2025  
**Managed Hosts**: 3 (david, pits, tristons-desk)  
**Deployment Status**: ⬜ Not Started | ⏳ In Progress | ✅ Complete

