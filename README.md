# codex-ssd-fix

Small macOS Ruby CLI for reducing Codex SSD churn without moving durable Codex state.
This will create a ramdisk and also decrease codex internal logging behavior as a fix to:
https://github.com/openai/codex/issues/28224

## Requirements

- macOS
- System Ruby
- macOS tools: `sqlite3`, `hdiutil`, `diskutil`

No install, `bundle install`, package manager, release artifact, or background service is required.

## Run

```sh
./bin/codex-ssd-fix help
# or
ruby -Ilib bin/codex-ssd-fix help
```

## Guided Setup

From a clone:

```sh
./scripts/setup
```

From a published repo, replace the URLs and paste:

```sh
CODEX_SSD_FIX_REPO_URL=https://github.com/OWNER/codex-ssd-fix.git \
  bash -c "$(curl -fsSL https://raw.githubusercontent.com/OWNER/codex-ssd-fix/main/scripts/setup)"
```

The script checks macOS dependencies, clones or updates into `~/.local/share/codex-ssd-fix`, runs `doctor`, then asks before applying the trace guard or mounting the RAM disk.

Commands:

- `./bin/codex-ssd-fix guard apply|status|remove`
- `./bin/codex-ssd-fix ramdisk mount|status|unmount`
- `./bin/codex-ssd-fix env`
- `./bin/codex-ssd-fix doctor`


## Typical Flow

```sh
./bin/codex-ssd-fix doctor
./bin/codex-ssd-fix guard apply --mode trace
./bin/codex-ssd-fix ramdisk mount
eval "$(./bin/codex-ssd-fix env)"
your-automation-command
./bin/codex-ssd-fix ramdisk unmount
```

`guard apply --mode trace` blocks high-volume trace rows while keeping normal logs. `--mode all` blocks all new log rows. Guard changes create a backup under:

```text
~/.codex/log-db-backups/<timestamp>/
```

Backups include `logs_2.sqlite` plus existing `logs_2.sqlite-wal` and `logs_2.sqlite-shm` sidecars.

## RAM Disk Safety

`ramdisk mount` creates `/Volumes/CodexRAMFix` and scratch dirs under `/Volumes/CodexRAMFix/codex-scratch`.

RAM disk data is volatile. Keep source code, important outputs, credentials, and `~/.codex` on durable storage. Do not set `CODEX_HOME` to a RAM disk path.

`env` prints scratch exports only when the RAM disk is mounted.

## Status and Cleanup

```sh
./bin/codex-ssd-fix doctor
./bin/codex-ssd-fix guard status
./bin/codex-ssd-fix ramdisk status
./bin/codex-ssd-fix guard remove
./bin/codex-ssd-fix ramdisk unmount
```

`guard remove` removes only tool-owned SQLite triggers and creates a backup first.

Manual restore: quit Codex, copy backed-up `logs_2.sqlite` and matching sidecars from `~/.codex/log-db-backups/<timestamp>/` back into `~/.codex/`, then confirm Codex starts. More detail: [docs/safety.md](docs/safety.md).

## Tests

```sh
ruby -Ilib:test test/*_test.rb
```

Optional if `rake` is already available:

```sh
rake test
```
