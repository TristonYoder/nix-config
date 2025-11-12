## Quick orientation for AI coding agents

This repo is a flake-based, multi-host Nix configuration (NixOS + nix-darwin) used to manage servers, desktops, and macOS laptops.
Provide concise, actionable edits: reference the flake entrypoints, host names, module locations, and secret handling. Keep changes minimal and preserve existing style.

- Big picture (what matters):
  - `flake.nix` is the canonical entrypoint. It exposes `nixosConfigurations` and `darwinConfigurations` for named hosts (e.g. `david`, `pits`, `tristons-desk`, `tyoder-mbp`, `Tristons-MacBook-Pro`). Use these attributes when building or referencing outputs.
  - Declarative structure: `common/` (shared system defaults), `profiles/` (role-based sets: `server.nix`, `desktop.nix`, `edge.nix`, `darwin.nix`), `modules/` (services split by category), `hosts/` (per-host configs + hardware files), `home/` (Home Manager user configs), `secrets/` (encrypted `.age` files and helper scripts).

- Typical developer workflows and safe commands to mention in PRs or patches:
  - Inspect: `nix flake show` to list outputs.
  - Test a build (NixOS): `nix build '.#nixosConfigurations.david.config.system.build.toplevel'` or use `sudo nixos-rebuild switch --flake .#david` to apply.
  - Test macOS (darwin): `nix build '.#darwinConfigurations.tyoder-mbp.config.system.build.toplevel'` then `sudo /tmp/result/sw/bin/darwin-rebuild switch --flake '.#tyoder-mbp'` or `darwin-rebuild switch --flake .#tyoder-mbp`.
  - Update inputs: `nix flake update` and validate with `nix flake check`.
  - Dev shell: `nix develop` (repo provides `devShells.default`).

- Project-specific conventions and patterns (be explicit):
  - Modules live under `modules/services/*` and expose option trees like `modules.services.<category>.<servicename>.enable` — enable/override via host `configuration.nix` or `profiles/*`.
  - Profiles are role-focused: prefer adding or disabling services by changing a host import or overriding profile defaults in `hosts/<name>/configuration.nix` rather than changing the profile in place unless you mean to affect many hosts.
  - Home Manager is integrated into system builds (home configs are imported in `flake.nix`). Do not run home-manager independently unless explicitly troubleshooting; prefer system rebuilds that include Home Manager.
  - Secrets are encrypted with agenix and expect `ssh-ed25519` recipients (not X25519). Use `secrets/encrypt-secret.sh` and `decrypt-secret.sh` helpers. Never add plain secrets to the repo.

- Integration points and external dependencies to reference in PRs:
  - `nixpkgs` / `nix-darwin` / `home-manager` inputs are defined in `flake.nix` (keep versions consistent when bumping inputs).
  - Docker-compose and standalone Docker services live under `docker/` (with subfolders for categories). Changes here may require different deployment steps.
  - CI/CD: GitHub Actions validate and deploy NixOS hosts (see `.github/workflows/`). If changing test matrix or host names, update workflows accordingly.

- How to propose changes (short checklist):
  1. Run `nix flake check` locally and `nix build` the target host attribute to reproduce the change.
 2. If changing secrets, demonstrate re-encryption with `secrets/encrypt-secret.sh` and avoid introducing plaintext.
 3. For service modules, follow existing module templates in `modules/` (options, `mkEnableOption`, Caddy integration patterns). Add tests where appropriate via `nix flake check`.

- Examples to copy when editing files:
  - Add/enable service in host: `modules.services.media.jellyfin.enable = true;` (put overrides in `hosts/<host>/configuration.nix`).
  - Build darwin toplevel: `nix build '.#darwinConfigurations.tyoder-mbp.config.system.build.toplevel'`.

Keep instructions focused on discoverable, current repository patterns. If anything in this file looks incomplete or you need more examples (e.g. exact GitHub Action host matrix edits), tell me which area to expand and I will iterate.
