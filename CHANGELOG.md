# Changelog

[Español](CHANGELOG.es.md)

NABU Setup and its manual are versioned separately. The script uses version numbers (such as 1.2.0); the manual uses revision numbers and states which script version it covers.

## NABU Setup 1.3.0 (2026-10-05)

- The virtual printer makes accented letters: an accent printed over a letter, the way WordStar does it with `^PH`, is drawn as a single letter (á, é, ñ, ü, ç, and the rest of Latin-1) and is stored that way in the text of the PDF.
- An ñ can also be typed with a hyphen or a `^` over the `n`, because the NABU keyboard has no `~` key.
- The virtual printer has two new letter-quality typefaces, *Serif* and *Sans serif*, besides the dot-matrix one, and it can print on blank paper as well as on continuous form. You choose them on the web panel.
- Each printout keeps its original data, and a new button on the panel redoes it with the chosen typeface and paper, without printing again from the NABU.
- New button on the web panel to delete each printout.
- Backups are now saved in `~/nabu/backups`. When this release is installed, any backups in `~/backups` are moved to the new folder automatically.
- Printing from WordStar is now verified on a real NABU.
- Fix: the `PAPER = False` option of earlier releases did not produce the PDF. The paper choice on the panel replaces it.

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
| 4 | 2026-10-05 | 1.3.0 | Accented letters, printing from WordStar, typeface and paper, deleting and redoing printouts, backups folder |
| 3 | 2026-10-04 | 1.2.0 | `nabu setup` command |
| 2 | 2026-10-04 | 1.1.0 | Safe shutdown: `nabu poweroff` and the panel button |
| 1 | 2026-10-03 | 1.0.0 | First release |
