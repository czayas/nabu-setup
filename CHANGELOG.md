# Changelog

[Español](CHANGELOG.es.md)

NABU Setup and its manual are versioned separately. The script uses version numbers (such as 1.2.0); the manual uses revision numbers and states which script version it covers.

## NABU Setup 1.4.0 (2026-10-07)

- The Internet Adapter starts without waiting for the Pi to be online, so the NABU can load sooner. On a Raspberry Pi 3 Model A+, the service went from starting about 31 seconds after power-on to about 12. On an existing installation, the change applies from the next time the Pi is powered on.
- Before starting the IA, the service waits up to ten seconds for the USB to RS-422 adapter to show up.
- New **News** card on the web panel, with the latest posts from nabu.ca. The panel gets them on its own, because the IA, starting without a network, shows the ones it had saved.
- The panel tells you when a newer Internet Adapter is available and when the IA has not loaded the latest news or channels. To do so, it compares the cloud's news and channel list with the copies the IA keeps.
- On the panel, the IA screen fits the width on its own and shows in full, with no horizontal scroll bar; tap it to enlarge it. Long log lines wrap onto the next line.
- The panel shows a visible banner when it cannot reach the Pi, turns the indicators gray instead of showing old data, and recovers on its own when the Pi is back, also after **Shut down the Pi**. It refreshes right away when you return to its tab and reloads on its own when a new release is installed.
- The panel has its own icon and name for adding it to a phone's home screen. With a `~/nabu/icon.png` file, your own icon is used.
- New local telnet, for logging in to the Pi from a terminal program on the NABU. It only accepts connections from the Pi itself (`127.0.0.1`). The installer asks only once whether to turn it on, and the new `nabu telnet` command shows it, turns it on (`on`), and turns it off (`off`). Sessions are adjusted on their own at login: the arrow keys work with Cloud CP/M's `telnet` command, and NABU Term80 sessions become a `vt100` terminal of 80 by 24.
- The repository now includes `tools/lq-fonts.py`, the program that builds the virtual printer's letter-quality typefaces.
- Removed the automatic move of backups from `~/backups` to `~/nabu/backups`. Anyone updating from 1.2.0 or earlier can move them by hand.

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
| 5 | 2026-10-07 | 1.4.0 | IA startup without waiting for the network; on the web panel, news, notices, a screen fitted to the width, a lost-connection notice, and an icon for the phone; local telnet |
| 4 | 2026-10-05 | 1.3.0 | Accented letters, printing from WordStar, typeface and paper, deleting and redoing printouts, backups folder |
| 3 | 2026-10-04 | 1.2.0 | `nabu setup` command |
| 2 | 2026-10-04 | 1.1.0 | Safe shutdown: `nabu poweroff` and the panel button |
| 1 | 2026-10-03 | 1.0.0 | First release |
