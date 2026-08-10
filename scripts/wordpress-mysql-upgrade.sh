#!/usr/bin/env bash
#
# Migrate the WordPress site databases from MySQL 5.7 (EOL Oct 2023) to 8.0.
#
# Strategy: dump/restore, not in-place. MySQL 8.0 rewrites a 5.7 data directory
# on first start and 5.7 can never read it again, so this writes into a NEW
# directory (database-8.0) and leaves the original untouched. That makes the
# whole migration reversible by reverting docker/websites/*.nix and rebuilding.
#
# Run ON david. Order matters:
#
#   1. ./wordpress-mysql-upgrade.sh dump     # while 5.7 is still running
#   2. rebuild                               # brings up empty 8.0 containers
#   3. ./wordpress-mysql-upgrade.sh restore  # loads the dumps into 8.0
#   4. ./wordpress-mysql-upgrade.sh verify   # check row counts + site HTTP
#
# Rollback at any point: revert docker/websites/*.nix, push, rebuild. The 5.7
# data directory is never written to by this script.

set -euo pipefail

DUMP_DIR="/data/docker-appdata/_mysql57-dumps"
APPDATA="/data/docker-appdata"

# site-key : db-container : wp-container : appdata-subdir
SITES=(
  "carolineyoder:com_carolineyoder-db:com_carolineyoder-wordpress:com-carolineyoder"
  "photography:photography_carolineelizabeth-db:photography_carolineelizabeth-wordpress:photography-carolineelizabeth"
  "studio:studio_7andco-db:studio_7andco-wordpress:studio-7andco"
)

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "==> $*"; }

# Read the root password out of the container's own environment. Avoids putting
# any credential in this file or on the command line (this repo is public).
db_root_pw() {
  docker exec "$1" printenv MYSQL_ROOT_PASSWORD
}

cmd_dump() {
  mkdir -p "$DUMP_DIR"
  chmod 700 "$DUMP_DIR"

  for entry in "${SITES[@]}"; do
    IFS=: read -r key db _wp _dir <<<"$entry"

    docker inspect "$db" >/dev/null 2>&1 || die "$db is not running — dump must happen before the rebuild"

    ver=$(docker exec "$db" mysql --version)
    case "$ver" in
      *5.7*) : ;;
      *) die "$db is not MySQL 5.7 (got: $ver). Already migrated? Refusing to overwrite dumps." ;;
    esac

    log "dumping $key from $db"
    pw=$(db_root_pw "$db")

    # --single-transaction keeps InnoDB consistent without locking the site out.
    # --routines/--triggers/--events so nothing is silently left behind.
    # --add-drop-database makes the restore idempotent: between the rebuild and
    # the restore the site is live against an empty DB, so WordPress may start
    # writing install-wizard tables. Dropping the schema first wipes anything it
    # created rather than colliding with it.
    docker exec -e MYSQL_PWD="$pw" "$db" \
      mysqldump -u root \
        --single-transaction \
        --routines --triggers --events \
        --default-character-set=utf8mb4 \
        --add-drop-database \
        --databases wordpress \
      > "$DUMP_DIR/$key.sql"

    size=$(stat -c %s "$DUMP_DIR/$key.sql")
    [ "$size" -gt 1024 ] || die "dump for $key is only ${size}B — refusing to continue"
    log "  wrote $DUMP_DIR/$key.sql (${size} bytes)"

    # Record row counts so `verify` can prove nothing was lost.
    docker exec -e MYSQL_PWD="$pw" "$db" \
      mysql -u root -N -B -e \
      "SELECT table_name, table_rows FROM information_schema.tables WHERE table_schema='wordpress' ORDER BY table_name;" \
      > "$DUMP_DIR/$key.counts.before" 2>/dev/null || true
  done

  log "dumps complete. Now commit+push and run: rebuild"
}

cmd_restore() {
  for entry in "${SITES[@]}"; do
    IFS=: read -r key db wp dir <<<"$entry"

    [ -f "$DUMP_DIR/$key.sql" ] || die "no dump at $DUMP_DIR/$key.sql — run '$0 dump' first"
    [ -d "$APPDATA/$dir/database" ] || log "WARNING: 5.7 data dir $APPDATA/$dir/database missing (rollback would not be possible)"

    ver=$(docker exec "$db" mysql --version)
    case "$ver" in
      *8.0*) : ;;
      *) die "$db is not MySQL 8.0 yet (got: $ver). Run 'rebuild' first." ;;
    esac

    # Wait for the fresh 8.0 instance to finish initialising.
    pw=$(db_root_pw "$db")
    log "waiting for $db to accept connections"
    for _ in $(seq 1 60); do
      if docker exec -e MYSQL_PWD="$pw" "$db" mysqladmin -u root ping --silent >/dev/null 2>&1; then
        break
      fi
      sleep 2
    done
    docker exec -e MYSQL_PWD="$pw" "$db" mysqladmin -u root ping --silent >/dev/null 2>&1 \
      || die "$db never became ready"

    log "restoring $key into $db"
    docker exec -i -e MYSQL_PWD="$pw" "$db" \
      mysql -u root --default-character-set=utf8mb4 < "$DUMP_DIR/$key.sql"

    # The dump recreates the `wordpress` schema but not the app user's grants,
    # which the 8.0 container created at init. Re-assert them to be safe.
    # Piped over stdin rather than passed with -e so the password never appears
    # in the process arguments.
    wp_user=$(docker exec "$db" printenv MYSQL_USER)
    wp_pw=$(docker exec "$db" printenv MYSQL_PASSWORD)
    printf "ALTER USER '%s'@'%%' IDENTIFIED BY '%s';\nGRANT ALL PRIVILEGES ON wordpress.* TO '%s'@'%%';\nFLUSH PRIVILEGES;\n" \
      "$wp_user" "$wp_pw" "$wp_user" \
      | docker exec -i -e MYSQL_PWD="$pw" "$db" mysql -u root

    log "  restarting WordPress container for $key"
    docker restart "$wp" >/dev/null
  done

  log "restore complete. Run: $0 verify"
}

cmd_verify() {
  local failed=0

  for entry in "${SITES[@]}"; do
    IFS=: read -r key db wp _dir <<<"$entry"
    pw=$(db_root_pw "$db")

    echo
    echo "--- $key ---"
    docker exec "$db" mysql --version

    docker exec -e MYSQL_PWD="$pw" "$db" \
      mysql -u root -N -B -e \
      "SELECT table_name, table_rows FROM information_schema.tables WHERE table_schema='wordpress' ORDER BY table_name;" \
      > "$DUMP_DIR/$key.counts.after" 2>/dev/null || true

    if [ -f "$DUMP_DIR/$key.counts.before" ]; then
      # table_rows is an InnoDB estimate, so compare the table SET, not exact counts.
      before=$(cut -f1 "$DUMP_DIR/$key.counts.before" | sort)
      after=$(cut -f1 "$DUMP_DIR/$key.counts.after" | sort)
      if [ "$before" = "$after" ]; then
        echo "tables: OK ($(echo "$after" | wc -l | tr -d ' ') tables present)"
      else
        echo "tables: MISMATCH"
        diff <(echo "$before") <(echo "$after") || true
        failed=1
      fi
    fi

    # Authoritative check: can WordPress itself talk to the DB?
    if docker exec "$wp" php -r \
      'include "/var/www/html/wp-config.php";
       $c = new mysqli(DB_HOST, DB_USER, DB_PASSWORD, DB_NAME);
       if ($c->connect_errno) { fwrite(STDERR, "connect failed: ".$c->connect_error."\n"); exit(1); }
       $r = $c->query("SELECT option_value FROM wp_options WHERE option_name=\"home\"");
       echo "home = ".$r->fetch_row()[0]."\n";' 2>&1 | grep -v '^PHP Warning'; then
      echo "wordpress db connection: OK"
    else
      echo "wordpress db connection: FAILED"
      failed=1
    fi
  done

  echo
  if [ "$failed" -eq 0 ]; then
    echo "All sites verified. The 5.7 data dirs under $APPDATA/*/database can be"
    echo "removed once you are satisfied — keep them at least a few days."
  else
    echo "VERIFICATION FAILED. To roll back: revert docker/websites/*.nix, push, rebuild."
    exit 1
  fi
}

case "${1:-}" in
  dump)    cmd_dump ;;
  restore) cmd_restore ;;
  verify)  cmd_verify ;;
  *) echo "usage: $0 {dump|restore|verify}" >&2; exit 2 ;;
esac
