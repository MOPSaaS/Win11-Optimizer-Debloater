## Summary

What does this PR change and why?

## Type

- [ ] Bug fix
- [ ] New tweak / feature
- [ ] Refactor
- [ ] Docs

## Safety checklist

- [ ] Does not touch Windows Update, Defender, Store, runtimes, or anti-cheat dependencies
- [ ] Every state-changing operation calls the matching `Backup-*` helper first
- [ ] Uses `Set-RegistryValueSafe` / `Disable-ServiceSafe` (idempotent)
- [ ] Logs at the right level (`Info`/`Success`/`Skip`/`Warning`/`Error`)
- [ ] CHANGELOG updated under `[Unreleased]`

## Local verification

- [ ] `Optimize Now` completes without errors in GUI log
- [ ] Snapshot JSON contains expected entries
- [ ] `Revert Changes` restores original state
- [ ] Re-running is a no-op (logs as `Skip`)
