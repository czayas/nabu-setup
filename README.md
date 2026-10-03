# NABU Setup

**English** · [Español](README.es.md)

NABU Setup is an installation script that turns a Raspberry Pi into a small server for the [NABU Personal Computer](https://en.wikipedia.org/wiki/NABU_Network). It downloads the official [NABU Internet Adapter](https://nabu.ca/downloads-nabu-internet-adapter), runs it as a service, and adds the tools to manage it from a terminal or a phone.

Current version: **1.0.0**, released on 2026-10-03. See the [changelog](CHANGELOG.md).

![The parts of a NABU server installed with NABU Setup](docs/img/architecture-en.png)

## What it installs

- **The NABU Internet Adapter as a service.** It starts when the Pi boots and restarts if it closes. It runs inside a `tmux` session, so you can open its text interface over SSH and leave it running.
- **The `nabu` command**, to check, start, stop, back up, and update the server.
- **A web panel** on port 80, password protected, with status indicators, control buttons, a live view of the Internet Adapter's screen, and the service log.
- **A virtual printer.** Whatever the NABU prints to the `LST:` device from Cloud CP/M becomes a PDF that looks like dot-matrix output on continuous paper. Bold, underline, and WordStar-style overstriking are supported.
- **Backups** of the CP/M drives, local programs, and settings as .zip files. The latest five are kept.

Everything besides the Internet Adapter is plain Bash and Python, with no libraries beyond the standard ones.

## Requirements

- A Raspberry Pi with an ARMv7 or ARMv8 processor: Pi 2, 3, 4, 5, or Zero 2 W. The Pi 1, Zero, and Zero W cannot run the Internet Adapter.
- Raspberry Pi OS Lite, 64-bit recommended, with SSH enabled.
- A USB to RS-422 adapter and a cable to the NABU. See [Make NABU Cable](https://nabu.ca/Make-NABU-Cable).

Version 1.0.0 was tested on a Raspberry Pi 3 Model A+.

## Installation

On the Pi, as your regular user:

```
wget https://raw.githubusercontent.com/czayas/nabu-setup/main/nabu-setup-en.sh
bash nabu-setup-en.sh
sudo reboot
```

The script asks for a password for the web panel and does the rest on its own. It is safe to run again, for example to change that password or to install a newer release.

There are two editions with the same code and different languages: `nabu-setup-en.sh` (English) and `nabu-setup-es.sh` (Spanish).

## The `nabu` command

| Command | What it does |
|---|---|
| `nabu` | Opens the Internet Adapter's interface. Leave with Ctrl-b, then d |
| `nabu status` | Service, RS-422 adapter, virtual printer, temperature, and power supply |
| `nabu list` | Service log and Internet Adapter errors |
| `nabu start`, `stop`, `restart` | Control the Internet Adapter |
| `nabu backup` | Saves a backup to `~/backups` |
| `nabu update` | Updates the Internet Adapter, after making a backup |
| `nabu version` | Shows the NABU Setup version and release date |
| `nabu help` | Shows the help |

The web panel is at `http://nabu.local` (user `nabu`). Printouts are saved in `~/nabu/printer`.

## Documentation

The user manual covers the NABU and its history, how to prepare the Pi, and a tutorial for every feature.

| | PDF | Source |
|---|---|---|
| English | [nabu-setup-manual-en.pdf](docs/nabu-setup-manual-en.pdf) | [docs/en/manual.md](docs/en/manual.md) |
| Spanish | [nabu-setup-manual-es.pdf](docs/nabu-setup-manual-es.pdf) | [docs/es/manual.md](docs/es/manual.md) |

The sources are Pandoc Markdown. To rebuild the PDFs you need `pandoc`, XeLaTeX (TeX Live, with Spanish language support), and the DejaVu Sans Mono font:

```
cd docs
make
```

## License

NABU Setup and its documentation are released under the [BSD 2-Clause License](LICENSE). The license covers NABU Setup only, not the NABU Internet Adapter, which the script downloads from its author's site.

## Credits

The NABU Internet Adapter, Cloud CP/M, and RetroNET are the work of DJ Sures ([nabu.ca](https://nabu.ca)). NABU Setup is an independent project and is not affiliated with nabu.ca.

NABU Setup is a project by Retro Informática Paraguay: <https://www.youtube.com/@retroinfopy>
