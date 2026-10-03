# Changelog

[Español](CHANGELOG.es.md)

NABU Setup and its manual are versioned separately. The script uses version numbers (1.0.0); the manual uses revision numbers and states which script version it covers.

## NABU Setup 1.0.0 (2026-10-03)

First public release.

- Installs the NABU Internet Adapter as a systemd service inside a `tmux` session.
- `nabu` administration command: `status`, `list`, `start`, `stop`, `restart`, `backup`, `update`, `version`, and `help`.
- Password-protected web panel on port 80.
- Virtual printer: whatever the NABU sends to `LST:` becomes a PDF in `~/nabu/printer`.
- Backups as .zip files in `~/backups`; the latest five are kept.
- Two editions with the same code: `nabu-setup-es.sh` (Spanish) and `nabu-setup-en.sh` (English).

## Manual

| Revision | Date | NABU Setup | Changes |
|---|---|---|---|
| 1 | 2026-10-03 | 1.0.0 | First release |
