# Changelog

[Español](CHANGELOG.es.md)

NABU Setup and its manual are versioned separately. The script uses version numbers (such as 1.2.0); the manual uses revision numbers and states which script version it covers.

## NABU Setup 1.2.0 (2026-10-04)

- New `nabu setup` command: downloads the latest published NABU Setup release, compares it with the installed one, and installs it.

## NABU Setup 1.1.0 (2026-10-04)

- New `nabu poweroff` command: shuts the Pi down safely before the power is cut.
- New **Shut down the Pi** button on the web panel.
- The installer now also lets the panel shut the Pi down without a password.

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
| 3 | 2026-10-04 | 1.2.0 | `nabu setup` command |
| 2 | 2026-10-04 | 1.1.0 | Safe shutdown: `nabu poweroff` and the panel button |
| 1 | 2026-10-03 | 1.0.0 | First release |
