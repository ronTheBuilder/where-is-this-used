# Codex Agent Instructions — where-is-this-used

## ⚠️ Sandbox Constraint: `sf` CLI Deploys

The Codex sandbox (`workspace-write` mode) only allows writes to:
- Project workdir
- `/tmp`, `$TMPDIR`
- `~/.codex/memories`

**`sf` CLI writes a daily log to `~/.sf/sf-YYYY-MM-DD.log`.**  
This is **outside** the sandbox and will fail with `SandboxDenied (EPERM)`.

### What this means for you:
- You **cannot** run `sf project deploy start`, `sf apex run test`, or any other `sf` command that initializes the logger
- `git` operations (add, commit, push) work fine
- File edits via `apply_patch` work fine
- Reading files, running tests locally = fine

### Workaround in sessions started with `--add-dir ~/.sf`:
If the Codex session was started with `--add-dir /Users/buurmanronbot/.sf`, you CAN run `sf` commands.

### If you don't have that flag:
- Do your code changes and git commit/push
- Leave a clear note for the human to run the deploy manually:
  ```
  sf project deploy start --source-dir force-app -o witu-dev --wait 10
  ```

## Model
Default: `gpt-5.3-codex`

## Project
Salesforce DX project in `/Users/buurmanronbot/Projects/where-is-this-used`
- Org alias: `witu-dev`
- Branch: `main`
- Commit as: `Simon <simon@hdconsulting.nl>`
