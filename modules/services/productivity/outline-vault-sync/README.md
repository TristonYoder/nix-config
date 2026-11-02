# outline-vault-sync

One-way publish of the Obsidian vault on david into Outline
(`outline.theyoder.family`). The vault is the only source of truth. Outline is
a read-only copy, and nothing here ever writes to the vault. Edits made in
Outline are overwritten the next time the note changes.

| Vault | Outline |
|---|---|
| Top-level folder | Collection (rename with `collectionNames`) |
| Note at the vault root | Document in the `rootCollection` collection (default: vault folder name) |
| Subfolder | Parent document. Its folder note (`A/B/B.md`, or `A/B.md` next to the folder) supplies the content; with no folder note the parent is empty |
| Note | Document under its folder |
| Deleted or renamed note | Old document **archived** (never deleted); a rename creates a new document |

## Units

Nothing runs unless Outline is also enabled on the host (`modules.services.productivity.outline.enable`).

| Unit | What it does |
|---|---|
| `outline-vault-sync-watch.service` | `inotifywait -m -r` on the vault. Starts the sync after `debounceSeconds` (60) with no further changes, or after `maxWaitSeconds` (600) of constant editing. Also syncs once at startup |
| `outline-vault-sync.service` | Oneshot sync. A start while it runs merges into that run, so the watcher waits for it to finish and starts it again |
| `outline-vault-sync-full.service` + `.timer` | Nightly (03:30) reconcile: the normal sync, plus a check that every mapped document is still live in Outline. Restores documents archived or trashed in Outline, and recreates ones that are gone |

The sync and the full reconcile take a lock on the state file, so they never
run concurrently.

### What a run does

1. Scans the vault and plans the tree. Every note is re-hashed on every run.
2. Pass 1: creates documents that are new (parents first). If there is no
   state entry, it first looks for an existing document with the same title
   under the same parent and adopts it, so lost state never makes duplicates.
3. Pass 2: renders every note and updates only those whose rendered output
   changed. That includes notes whose links now resolve to a just-created
   document.
4. Pass 3: archives documents whose note is gone.

Transforms: YAML frontmatter and the leading `# H1` are stripped. `[[note]]`,
`[[note|alias]]`, `[[note#heading]]` and relative `.md` links become Outline
document links, and unresolvable ones become plain text. `![[image.png]]` is
uploaded with `attachments.create` and embedded. Callouts become blockquotes
with a bold title. Dataview blocks and inline queries are dropped, and
`%% comments %%` are removed. Links into excluded paths stay plain text, and
excluded attachments are never uploaded.

### Excludes

`excludes` takes vault-relative globs (default `.obsidian/`, `.trash/`,
`AIOS/history/`). Hidden files and folders, Syncthing artifacts
(`.stfolder`, `.stversions`, `*.sync-conflict-*`, `.syncthing.*.tmp`,
`~syncthing~*.tmp`), and editor swap or backup files are always ignored, by
both the watcher and the sync. Adding an exclude archives the documents it
now hides on the next run, subject to the mass-archive guard.

## Security

- Runs as the system user `outline-vault-sync`, never as a login user.
- Read access is a POSIX ACL (`u:outline-vault-sync:rX`, plus a default ACL
  on directories), applied by the root oneshot `outline-vault-sync-acl.service`, which the watcher and both sync units pull in before every run.
  It is reapplied each time because Syncthing reapplies the sending device's
  mode bits, and a `chmod` on a file with an ACL rewrites its mask. It only
  ever adds read for this user.
- Sandbox: `ProtectSystem=strict`, `ProtectHome=tmpfs`, `/data` replaced by
  an empty read-only tmpfs, and the vault bind-mounted read-only. The only
  writable path is `/var/lib/outline-vault-sync`. Also `NoNewPrivileges`,
  no capabilities, and a syscall filter.
- The API key comes from agenix through `LoadCredential=` and is read from
  `$CREDENTIALS_DIRECTORY/token` at runtime. It is never in the Nix store or
  the unit environment.
- A polkit rule lets this user `start` `outline-vault-sync.service` and
  nothing else.
- Collections the sync creates are private (`collectionPermission = null`)
  unless configured otherwise. `protectedCollections` (default `Welcome`) are
  never written to.

## Deployment

1. In Outline: Settings → API & Apps → New API key (full access, no
   expiry). Copy it.
2. Encrypt it (from the repo root, on the feature branch). Paste the key
   when prompted, then press Enter and Ctrl+D. Leave out `-e`: that wraps
   the value in `KEY=value` env format, and this secret is the bare key.

   ```bash
   cd secrets && ./encrypt-secret.sh -n outline-vault-sync-token.age -h david --git-add
   ```

3. Set `modules.services.productivity.outlineVaultSync.enable = true` in
   `hosts/david/configuration.nix`, then commit, push and `rebuild`.
4. Check the first run. It creates every document, so it is slow, because
   `documents.create` is rate-limited to 25/min:

   ```bash
   journalctl -u outline-vault-sync -f
   ```

## Operations

```bash
# Logs: one summary line per run, plus a line per create/update/archive and every error
journalctl -u outline-vault-sync -u outline-vault-sync-full -n 100
journalctl -u outline-vault-sync-watch -f      # "change detected" / "starting sync"
journalctl -u outline-vault-sync --grep 'sync done'

# Sync now
sudo systemctl start outline-vault-sync

# Full reconcile now (verify every document still exists in Outline)
sudo systemctl start outline-vault-sync-full

# Preview: what would be created/updated/archived, without changing anything
sudo systemd-run --pipe --wait -p User=outline-vault-sync -p LoadCredential=token:/run/agenix/outline-vault-sync-token \
  -p StateDirectory=outline-vault-sync \
  $(systemctl show -P ExecStart outline-vault-sync | grep -o '/nix/store/[^ ]*/bin/outline-vault-sync --config [^ ;]*') --dry-run

# Offline: print the planned tree, or one note as it would be uploaded (no token needed)
CMD=$(systemctl show -P ExecStart outline-vault-sync | grep -o '/nix/store/[^ ]*/bin/outline-vault-sync --config [^ ;]*')
sudo $CMD --list
sudo $CMD --render 'Homelab/nix-config.md'
```

### Force a full resync (re-upload everything)

Reset the state file. The next run adopts the existing documents by
collection and title path, then re-uploads every one of them. Nothing is
duplicated. Attachments are uploaded again, and the previous copies are left
orphaned in Outline.

```bash
sudo systemctl stop outline-vault-sync-watch
sudo rm /var/lib/outline-vault-sync/state.json
sudo systemctl start outline-vault-sync-full
sudo systemctl start outline-vault-sync-watch
```

State (`/var/lib/outline-vault-sync/state.json`) maps each vault path to
`{id, url, collectionId, contentHash, renderedHash}`. It is safe to delete at
any time.

### Mass-archive guard

A run that would archive more than `maxArchivePerRun` (20) documents archives
none of them, logs `refusing to archive N documents` with examples, and fails.
This usually means the vault is half-synced or an exclude was widened. If it
is intended:

```bash
sudo touch /var/lib/outline-vault-sync/allow-mass-archive
sudo systemctl start outline-vault-sync
```

The flag is consumed by that run.

A vault that is missing or contains no notes aborts the run before it touches
Outline. Files the service cannot read are logged as errors and never treated
as deleted.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `cannot read <path> (permission denied)` | The ACL did not apply. Check `getfacl "<path>"` for `user:outline-vault-sync:r--` and an effective mask that is not `---`. The ACL is reapplied at the next sync start |
| `HTTP 401` | Key revoked or expired. Create a new one and re-encrypt `outline-vault-sync-token.age` |
| `HTTP 429, backing off` | Expected during large runs; the sync honours `Retry-After` and continues |
| Watcher restarting with `inotifywait exited` | Usually too many watches. Check `/proc/sys/fs/inotify/max_user_watches` (the vault needs about one per folder) |
| Edits in Outline disappeared | By design: Outline is a copy. Edit the vault |
| A document was archived after a rename | By design: a rename is archive + create. Restore the old one from Outline's archive if needed |
| Duplicate document after manually moving one in Outline | Adoption matches by collection + parent + title. Move it back, or archive the duplicate and run the full reconcile |
