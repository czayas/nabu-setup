#!/usr/bin/env bash
# NABU Setup — a minimal NABU server for Raspberry Pi (Raspberry Pi OS Lite)
# Version 1.0.0 · released on 2026-10-03 · English edition
#
# Retro Informática Paraguay — https://www.youtube.com/@retroinfopy
# Repository and user manual: https://github.com/czayas/nabu-setup
#
# Copyright (c) 2026, Retro Informática Paraguay
# BSD 2-Clause License: see the LICENSE file in the repository
# SPDX-License-Identifier: BSD-2-Clause
#
# What it does:
#   - Installs tmux/unzip/wget/python3 and gives your user serial port access
#   - Downloads the official NABU Internet Adapter (nabu.ca) for your architecture
#   - Runs it as a systemd service inside a tmux session: it starts on its own
#     when the Pi boots, and you can open its interface over SSH
#   - Installs the `nabu` administration command
#   - Installs a lightweight, password-protected web panel (port 80: http://nabu.local)
#   - Installs the virtual printer: whatever the NABU sends to LST: from Cloud CP/M
#     is saved as a PDF in ~/nabu/printer and shows up on the panel
#
# Usage (on the Pi, as your regular user, NOT with sudo):
#   bash nabu-setup-en.sh
# It is safe to run again (for example, to change the panel password or to
# apply a newer release of this script). If the Internet Adapter is already
# installed, it is neither downloaded again nor restarted.
#
# NABU Setup is an independent project: it is not affiliated with nabu.ca or
# with the author of the NABU Internet Adapter.
set -euo pipefail

NABU_SETUP_VERSION="1.0.0"
NABU_SETUP_DATE="2026-10-03"
NABU_SETUP_LANG="en"
NABU_SETUP_REPO="https://github.com/czayas/nabu-setup"

case "${1:-}" in
  "") ;;
  -v|--version)
    echo "NABU Setup $NABU_SETUP_VERSION ($NABU_SETUP_DATE)"
    exit 0 ;;
  -h|--help)
    cat <<TXT
NABU Setup $NABU_SETUP_VERSION ($NABU_SETUP_DATE)
Installs and configures a NABU server on a Raspberry Pi.

Usage: bash $(basename "$0") [--version | --help]

With no options, it installs or updates the server. Run it as your regular
user; the script calls sudo when it needs to.
User manual: $NABU_SETUP_REPO
TXT
    exit 0 ;;
  *)
    echo "Unknown option: $1 (try --help)"
    exit 1 ;;
esac

if [[ $EUID -eq 0 ]]; then
  echo "Run it as your regular user (the script calls sudo when it needs to)."
  exit 1
fi

echo "NABU Setup $NABU_SETUP_VERSION ($NABU_SETUP_DATE)"
echo

U="$USER"
DIR="$HOME/nabu"
PRINT_DIR="$DIR/printer"
PORT=80

# The Internet Adapter is built on .NET, which does not run on ARMv6 processors
if [[ "$(uname -m)" == armv6l ]]; then
  echo "This Raspberry Pi has an ARMv6 processor (Pi 1, Zero or Zero W)."
  echo "The Internet Adapter needs ARMv7 or later: Pi 2, 3, 4, 5 or Zero 2 W."
  exit 1
fi

# The package is chosen by the installed system (32 or 64 bit), not the processor
case "$(dpkg --print-architecture 2>/dev/null || uname -m)" in
  arm64|aarch64)  ZIP=linux-arm64.zip ;;
  armhf|armv7l)   ZIP=linux-arm.zip ;;
  amd64|x86_64)   ZIP=linux-x64.zip ;;
  *) echo "Unsupported architecture: $(uname -m)"; exit 1 ;;
esac
URL="https://cloud.nabu.ca/$ZIP"

# ---------------------------------------------------------------------------
# Web panel password (asked up front so nothing interrupts the install later)
# ---------------------------------------------------------------------------
ASK_PW=1
if [[ -f /etc/nabu-web.conf ]]; then
  read -rp "The web panel already has a password. Change it? [y/N] " r
  [[ "${r,,}" == y* ]] || ASK_PW=0
fi
if [[ $ASK_PW -eq 1 ]]; then
  while true; do
    read -rsp "Password for the web panel (user: nabu): " PW1; echo
    read -rsp "Type it again: " PW2; echo
    if [[ -n "$PW1" && "$PW1" == "$PW2" ]]; then break; fi
    echo "They do not match, or the password is empty. Try again."
  done
fi

PACKAGES="tmux unzip wget python3"
if dpkg -s $PACKAGES >/dev/null 2>&1; then
  echo "==> Packages already installed"
else
  echo "==> Installing packages"
  sudo apt-get update
  sudo apt-get install -y $PACKAGES
fi

echo "==> Giving $U access to the serial port and the system log"
sudo usermod -aG dialout,systemd-journal "$U"

mkdir -p "$DIR"
BINPATH="$(find "$DIR" -maxdepth 3 -type f -name 'NABU-Internet*Adapter-84' | head -n1 || true)"
if [[ -n "$BINPATH" ]]; then
  FIRST=0
  echo "==> The Internet Adapter is already installed; not downloading it again"
  echo "    (to update it: nabu update)"
else
  FIRST=1
  echo "==> Downloading the Internet Adapter ($ZIP)"
  wget -q --show-progress -O "/tmp/$ZIP" "$URL"
  unzip -o -q "/tmp/$ZIP" -d "$DIR"
  rm -f "/tmp/$ZIP"
  BINPATH="$(find "$DIR" -maxdepth 3 -type f -name 'NABU-Internet*Adapter-84' | head -n1 || true)"
  if [[ -z "$BINPATH" ]]; then
    echo "The Internet Adapter program was not found inside the ZIP. Check $DIR"
    exit 1
  fi
fi
chmod +x "$BINPATH"
BINDIR="$(dirname "$BINPATH")"
echo "    Program: $BINPATH"

# The IA looks for "libdl.so" (unversioned), which is gone since glibc 2.34.
# Without this link the text interface does not start (error in Curses.endwin).
echo "==> Linking libdl.so in the IA's folder"
LIBDL="$(/sbin/ldconfig -p | awk '/libdl\.so\.2 /{print $NF; exit}')"
if [[ -n "$LIBDL" ]]; then
  ln -sfn "$LIBDL" "$BINDIR/libdl.so"
  echo "    libdl.so -> $LIBDL"
else
  echo "    WARNING: libdl.so.2 was not found; the IA may fail to start."
fi

echo "==> tmux configuration for the IA"
cat > "$DIR/tmux.conf" <<'EOF'
set -g default-terminal "xterm-256color"
set -g mouse on
set -g status-style "bg=colour19,fg=white"
set -g status-left " NABU IA "
set -g status-right " Ctrl-b d = leave it running "
set -g status-right-length 40
EOF

echo "==> Saving /etc/nabu-ia.conf"
sudo tee /etc/nabu-ia.conf >/dev/null <<EOF
NABU_DIR="$DIR"
NABU_BIN="$BINPATH"
NABU_ZIP="$ZIP"
NABU_URL="$URL"
NABU_PORT="$PORT"
NABU_PRINT_DIR="$PRINT_DIR"
NABU_SETUP_VERSION="$NABU_SETUP_VERSION"
NABU_SETUP_DATE="$NABU_SETUP_DATE"
NABU_SETUP_LANG="$NABU_SETUP_LANG"
NABU_SETUP_REPO="$NABU_SETUP_REPO"
EOF

echo "==> Creating the nabu-ia systemd service"
sudo tee /etc/systemd/system/nabu-ia.service >/dev/null <<EOF
[Unit]
Description=NABU Internet Adapter (in a tmux session)
After=network-online.target
Wants=network-online.target
# If the IA fails 10 times within 5 minutes, systemd stops retrying
StartLimitIntervalSec=300
StartLimitBurst=10

[Service]
Type=forking
User=$U
WorkingDirectory=$BINDIR
Environment=TERM=xterm-256color
# The IA's errors (stderr) go to ia-error.log without disturbing the screen
ExecStart=/usr/bin/tmux -L nabu -f $DIR/tmux.conf new-session -d -s nabu -x 100 -y 35 "exec $BINPATH 2>>$DIR/ia-error.log"
ExecStop=-/usr/bin/tmux -L nabu kill-server
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

echo "==> Allowing the service to be controlled without a password (for the web panel)"
SYSTEMCTL="$(command -v systemctl)"
sudo tee /etc/sudoers.d/nabu >/dev/null <<EOF
$U ALL=(root) NOPASSWD: $SYSTEMCTL start nabu-ia, $SYSTEMCTL stop nabu-ia, $SYSTEMCTL restart nabu-ia, $SYSTEMCTL reset-failed nabu-ia
EOF
sudo chmod 440 /etc/sudoers.d/nabu
sudo visudo -cf /etc/sudoers.d/nabu >/dev/null

echo "==> Installing the administration command: nabu"
sudo tee /usr/local/bin/nabu >/dev/null <<'EOF'
#!/usr/bin/env bash
# nabu — NABU server administration (part of NABU Setup)
source /etc/nabu-ia.conf
PRINT_DIR="${NABU_PRINT_DIR:-$NABU_DIR/printer}"
VERSION="NABU Setup ${NABU_SETUP_VERSION:-?} (${NABU_SETUP_DATE:-?})"

usage() {
  cat <<TXT
$VERSION
Usage: nabu [command]

  nabu            Opens the Internet Adapter's interface
                  (to leave without closing it: Ctrl-b, then d)
  nabu status     Service status, RS422 adapter, virtual printer,
                  temperature and power supply
  nabu list       Last lines of the service log and of the IA's errors
  nabu start      Starts the Internet Adapter
  nabu stop       Stops the Internet Adapter
  nabu restart    Restarts the Internet Adapter
  nabu backup     Saves a .zip backup of CP/M and the settings to ~/backups
                  (the latest 5 are kept)
  nabu update     Downloads the latest IA release (makes a backup first)
  nabu version    Shows the NABU Setup version and release date
  nabu help       Shows this help

Web panel: http://$(hostname).local$([[ "${NABU_PORT:-80}" != 80 ]] && echo ":$NABU_PORT")  (user: nabu)
Printouts: whatever the NABU sends to LST: is saved as a PDF in ${PRINT_DIR/#$HOME/\~}
TXT
}

case "${1:-}" in
  "")
    if ! tmux -L nabu has-session -t nabu 2>/dev/null; then
      echo "The Internet Adapter is not running. Try: nabu start"
      exit 1
    fi
    exec tmux -L nabu attach -t nabu ;;
  status)
    systemctl --no-pager --lines=0 status nabu-ia
    echo
    ls -l /dev/ttyUSB* 2>/dev/null || echo "RS422 adapter: NOT detected"
    if [[ "$(systemctl is-active nabu-print 2>/dev/null)" == active ]]; then
      n=$(find "$PRINT_DIR" -maxdepth 1 -name 'print-*.pdf' 2>/dev/null | wc -l)
      echo "Virtual printer: running (printouts in ${PRINT_DIR/#$HOME/\~}: $n)"
    else
      echo "Virtual printer: stopped"
    fi
    if command -v vcgencmd >/dev/null; then
      vcgencmd measure_temp
      t=$(vcgencmd get_throttled | cut -d= -f2)
      if [[ "$t" == "0x0" ]]; then echo "Power supply: OK";
      else echo "Power supply: PROBLEMS (throttled=$t, check the power adapter)"; fi
    fi ;;
  list)
    journalctl -u nabu-ia -n 30 --no-pager
    if [[ -s "$NABU_DIR/ia-error.log" ]]; then
      echo
      echo "--- Internet Adapter errors ($NABU_DIR/ia-error.log) ---"
      tail -n 20 "$NABU_DIR/ia-error.log"
    fi ;;
  start|restart)
    sudo systemctl reset-failed nabu-ia 2>/dev/null
    exec sudo systemctl "$1" nabu-ia ;;
  stop)
    exec sudo systemctl stop nabu-ia ;;
  backup)
    exec python3 /usr/local/lib/nabu/nabu-backup.py ;;
  update)
    set -e
    tmp="/tmp/$NABU_ZIP"
    echo "Downloading $NABU_URL"
    wget -q --show-progress --progress=dot:giga -O "$tmp" "$NABU_URL"
    python3 /usr/local/lib/nabu/nabu-backup.py
    sudo systemctl stop nabu-ia
    unzip -o -q "$tmp" -d "$NABU_DIR"
    chmod +x "$NABU_BIN"
    rm -f "$tmp"
    sudo systemctl start nabu-ia
    echo "Done. The Internet Adapter was updated and is running again." ;;
  version)
    echo "$VERSION"
    [[ -n "${NABU_SETUP_REPO:-}" ]] && echo "$NABU_SETUP_REPO"
    exit 0 ;;
  help)
    usage ;;
  *)
    echo "Unknown command: $1"
    echo
    usage
    exit 1 ;;
esac
EOF
sudo chmod +x /usr/local/bin/nabu

echo "==> Installing the backup tool"
sudo mkdir -p /usr/local/lib/nabu
sudo tee /usr/local/lib/nabu/nabu-backup.py >/dev/null <<'PYEOF'
#!/usr/bin/env python3
"""Creates a .zip backup of the Internet Adapter's data: CP/M drives
(Store/), local programs and settings. Leaves out the program itself, the
cache, the logs and the virtual printer's PDFs.
Saves to ~/backups and keeps only the latest KEEP files."""
import datetime, glob, os, sys, zipfile

KEEP = 5
CONF = os.environ.get("NABU_IA_CONF", "/etc/nabu-ia.conf")
DEST = os.environ.get("NABU_BACKUP_DIR", os.path.expanduser("~/backups"))
EXCL_DIRS = {"Cache"}
EXCL_FILES = {"CommLog.txt", "Console.txt", "ia-error.log", "libdl.so",
              "README.TXT", "SERVICE.TXT", "tmux.conf"}


def conf():
    c = {}
    with open(CONF) as f:
        for line in f:
            if "=" in line:
                k, v = line.strip().split("=", 1)
                c[k] = v.strip('"')
    return c


def main():
    c = conf()
    binpath = c["NABU_BIN"]
    base = os.path.dirname(binpath)
    # Printouts stay out of the backup even though they live inside the folder
    prints = os.path.abspath(c.get("NABU_PRINT_DIR") or os.path.join(base, "printer"))
    excl = EXCL_FILES | {os.path.basename(binpath)}
    os.makedirs(DEST, exist_ok=True)

    stamp = datetime.datetime.now().strftime("%Y-%m-%d-%H%M")
    out = os.path.join(DEST, f"nabu-backup-{stamp}.zip")
    if os.path.exists(out):  # two backups within the same minute
        out = os.path.join(DEST, f"nabu-backup-{stamp}{datetime.datetime.now():%S}.zip")
    tmp = out + ".part"

    n = 0
    with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as z:
        for root, dirs, files in os.walk(base):
            dirs[:] = sorted(d for d in dirs if d not in EXCL_DIRS
                             and os.path.abspath(os.path.join(root, d)) != prints)
            rel_root = os.path.relpath(root, base)
            # empty folders (drives and user areas with no files)
            if rel_root != "." and not files:
                z.writestr(os.path.join("nabu", rel_root) + "/", "")
            for name in sorted(files):
                path = os.path.join(root, name)
                if (name in excl or os.path.islink(path)
                        or name.endswith(".so") or ".so." in name):
                    continue
                z.write(path, os.path.join("nabu", rel_root, name))
                n += 1
    os.replace(tmp, out)

    olds = sorted(glob.glob(os.path.join(DEST, "nabu-backup-*.zip")))
    for old in olds[:-KEEP]:
        os.remove(old)

    size = os.path.getsize(out) / 1024
    print(f"Backup created: {out} ({n} files, {size:.0f} KB)")
    print(f"Backups kept in {DEST}: {min(len(olds), KEEP)} (maximum {KEEP})")
    return out


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"Could not create the backup: {e}", file=sys.stderr)
        sys.exit(1)
PYEOF
sudo chmod 755 /usr/local/lib/nabu/nabu-backup.py

echo "==> Installing the virtual printer (LST.TXT to PDF)"
sudo tee /usr/local/lib/nabu/nabu-print.py >/dev/null <<'PYEOF'
#!/usr/bin/env python3
"""Virtual printer for the NABU server.

Watches LST.TXT, the file where the Internet Adapter stores whatever the NABU
sends to the printer (the LST: device in Cloud CP/M). Once the file has stopped
growing for WAIT seconds, it takes the new data and renders a PDF that looks
like dot-matrix output on continuous paper, saved in the printouts folder
(NABU_PRINT_DIR in /etc/nabu-ia.conf; normally ~/nabu/printer).

Standard library only. It never modifies LST.TXT: it remembers how far it read.

It can also convert a single file:
    python3 nabu-print.py input.txt output.pdf
"""
import datetime, json, os, sys, time, zlib

CONF = os.environ.get("NABU_IA_CONF", "/etc/nabu-ia.conf")

WAIT = 5       # seconds without new data before a print job is considered done
PAPER = True   # False: plain letter-size sheet, no green bars or sprocket holes
COLS = 80      # columns per line (10 characters per inch)
LPP = 66       # lines per page (6 lines per inch on an 11-inch sheet)

TITLE = "NABU printout %s"         # PDF title; carries the date and time
TITLE_DATE = "%m/%d/%Y %H:%M:%S"


def read_conf():
    """Reads /etc/nabu-ia.conf (KEY="value" lines). Returns {} if missing."""
    conf = {}
    try:
        with open(CONF) as f:
            for line in f:
                if "=" in line:
                    k, v = line.strip().split("=", 1)
                    conf[k] = v.strip('"')
    except OSError:
        pass
    return conf


DEST = (os.environ.get("NABU_PRINT_DIR") or read_conf().get("NABU_PRINT_DIR")
        or os.path.expanduser("~/nabu/printer"))
STATE = os.path.join(DEST, ".state.json")

# 5x7 dot-matrix font, characters 0x20 to 0x7E. Five bytes per character,
# one per column; bit 0 is the top row.
GLYPHS = bytes.fromhex(
    "0000000000" "00005F0000" "0007000700" "147F147F14" "242A7F2A12"
    "2313086462" "3649552250" "0005030000" "001C224100" "0041221C00"
    "14083E0814" "08083E0808" "0050300000" "0808080808" "0060600000"
    "2010080402" "3E5149453E" "00427F4000" "4261514946" "2141454B31"
    "1814127F10" "2745454539" "3C4A494930" "0171090503" "3649494936"
    "064949291E" "0036360000" "0056360000" "0814224100" "1414141414"
    "0041221408" "0201510906" "324979413E" "7E1111117E" "7F49494936"
    "3E41414122" "7F4141221C" "7F49494941" "7F09090901" "3E4149497A"
    "7F0808087F" "00417F4100" "2040413F01" "7F08142241" "7F40404040"
    "7F020C027F" "7F0408107F" "3E4141413E" "7F09090906" "3E4151215E"
    "7F09192946" "4649494931" "01017F0101" "3F4040403F" "1F2040201F"
    "3F4038403F" "6314081463" "0708700807" "6151494543" "007F414100"
    "0204081020" "0041417F00" "0402010204" "4040404040" "0001020400"
    "2054545478" "7F48444438" "3844444420" "384444487F" "3854545418"
    "087E090102" "0C5252523E" "7F08040478" "00447D4000" "2040443D00"
    "7F10284400" "00417F4000" "7C04180478" "7C08040478" "3844444438"
    "7C14141408" "081414187C" "7C08040408" "4854545420" "043F444020"
    "3C4040207C" "1C2040201C" "3C4030403C" "4428102844" "0C5050503C"
    "4464544C44" "0008364100" "00007F0000" "0041360800" "0804081008")

NAMES = (
    "space exclam quotedbl numbersign dollar percent ampersand quotesingle "
    "parenleft parenright asterisk plus comma hyphen period slash zero one "
    "two three four five six seven eight nine colon semicolon less equal "
    "greater question at").split() + list("ABCDEFGHIJKLMNOPQRSTUVWXYZ") + (
    "bracketleft backslash bracketright asciicircum underscore grave"
    ).split() + list("abcdefghijklmnopqrstuvwxyz") + (
    "braceleft bar braceright asciitilde").split()

# Letters with descenders, drawn on 9 rows instead of 7.
DESCENDERS = {
    "g": (".....", ".....", ".####", "#...#", "#...#", "#...#", ".####", "....#", ".###."),
    "j": ("....#", ".....", "...##", "....#", "....#", "....#", "....#", "#...#", ".###."),
    "p": (".....", ".....", "####.", "#...#", "#...#", "#...#", "####.", "#....", "#...."),
    "q": (".....", ".....", ".####", "#...#", "#...#", "#...#", ".####", "....#", "....#"),
    "y": (".....", ".....", "#...#", "#...#", "#...#", "#...#", ".####", "....#", ".###."),
}

# Epson codes (ESC + letter) that take one parameter and are ignored.
ESC_1 = set(b"WSpxk!A3JNQlRtaUsij")
ESC_GRAPHICS = set(b"KLYZ")


# ---------------------------------------------------------------------------
# Interpreter: turns the bytes the printer received into pages
# ---------------------------------------------------------------------------
class Printer:
    """Simulates the print head: column, row, carriage return, line feed,
    form feed, tab, backspace and overstrike."""

    def __init__(self):
        self.pages = [{}]        # page: {row: {column: [(character, bold)]}}
        self.row = self.col = 0
        self.bold = self.underline = False
        self.pending = {}        # what was printed since the last carriage return

    def _line_feed(self):
        self.row += 1
        if self.row >= LPP:
            self._new_page()

    def _new_page(self):
        self.pages.append({})
        self.row = 0

    def _settle(self):
        """Commits to the page what was printed since the last carriage return.

        A carriage return without a line feed prints over the same line again.
        That is honored when it is a genuine overstrike, the kind WordStar
        uses: bold (the same character again), underline (underscore),
        strikeout (hyphens) or accents. If instead a letter or digit would
        cover a different one, it is treated as a new line.
        """
        if not self.pending:
            return
        line = self.pages[-1].get(self.row, {})
        clash = any(
            old != ch and old.isalnum() and ch.isalnum()
            for col, strikes in self.pending.items() if col in line
            for ch, _ in strikes for old, _ in line[col])
        if clash:
            self._line_feed()
        line = self.pages[-1].setdefault(self.row, {})
        for col, strikes in self.pending.items():
            line.setdefault(col, []).extend(strikes)
        self.pending = {}

    def _put(self, ch):
        if self.col >= COLS:               # line is too long: wrap to the next
            self._settle()
            self._line_feed()
            self.col = 0
        strikes = []
        if ch != " ":
            strikes.append((ch, self.bold))
        if self.underline:
            strikes.append(("_", False))
        if strikes:
            self.pending.setdefault(self.col, []).extend(strikes)
        self.col += 1

    def _escape(self, d, i):
        """Consumes an Epson printer ESC sequence. Applies bold and underline;
        everything else (typefaces, graphics) is ignored."""
        n = len(d)
        if i >= n:
            return i
        c = d[i]
        i += 1
        if c == 0x40:                      # ESC @  reset
            self.bold = self.underline = False
        elif c in b"EG":                   # bold / double strike
            self.bold = True
        elif c in b"FH":
            self.bold = False
        elif c == 0x2D:                    # ESC - n  underline
            if i < n:
                self.underline = d[i] in (1, 0x31)
            i += 1
        elif c in ESC_1:
            i += 1
        elif c == 0x43:                    # ESC C n  or  ESC C 0 n
            if i < n and d[i] == 0:
                i += 1
            i += 1
        elif c in b"DB":                   # tab stop list, ends with NUL
            while i < n and d[i] != 0:
                i += 1
            i += 1
        elif c in ESC_GRAPHICS:            # ESC K n1 n2 data...
            i = i + 2 + d[i] + 256 * d[i + 1] if i + 1 < n else n
        elif c == 0x2A:                    # ESC * m n1 n2 data...
            i = i + 3 + d[i + 1] + 256 * d[i + 2] if i + 2 < n else n
        return min(i, n)

    def feed(self, data):
        i, n = 0, len(data)
        while i < n:
            b = data[i]
            i += 1
            if b == 0x1B:
                i = self._escape(data, i)
            elif b == 0x0D:                # carriage return
                self._settle()
                self.col = 0
            elif b in (0x0A, 0x0B):        # line feed
                self._settle()
                self._line_feed()
                self.col = 0
            elif b == 0x0C:                # form feed
                self._settle()
                if self.row or self.pages[-1]:
                    self._new_page()
                self.col = 0
            elif b == 0x09:                # tab stop every 8 columns
                self.col = min((self.col // 8 + 1) * 8, COLS)
            elif b == 0x08:                # backspace
                self.col = max(0, self.col - 1)
            elif b >= 0x20 and 0x20 <= b & 0x7F <= 0x7E:
                self._put(chr(b & 0x7F))
        self._settle()
        while len(self.pages) > 1 and not self.pages[-1]:
            self.pages.pop()
        return self.pages


# ---------------------------------------------------------------------------
# PDF
# ---------------------------------------------------------------------------
def _n(v):
    return ("%.2f" % v).rstrip("0").rstrip(".")


def _circle(x, y, r):
    k = r * 0.5523
    p = [x + r, y, x + r, y + k, x + k, y + r, x, y + r,
         x - k, y + r, x - r, y + k, x - r, y,
         x - r, y - k, x - k, y - r, x, y - r,
         x + k, y - r, x + r, y - k, x + r, y]
    t = [_n(v) for v in p]
    return ("%s %s m %s %s %s %s %s %s c %s %s %s %s %s %s c "
            "%s %s %s %s %s %s c %s %s %s %s %s %s c h\n" % tuple(t))


def _dots(ch):
    """Dots (column, row) of a character. Rows 0 to 6 sit on the baseline;
    7 and 8 go below it, like the lower pins of a 9-pin printer."""
    if ch in DESCENDERS:
        return [(i, f) for f, row in enumerate(DESCENDERS[ch])
                for i, c in enumerate(row) if c == "#"]
    if ch == "_":                          # underlines without touching the letter
        return [(i, 8) for i in range(5)]
    base = (ord(ch) - 32) * 5
    return [(i, f) for i, bits in enumerate(GLYPHS[base:base + 5])
            for f in range(7) if bits >> f & 1]


def _glyph(ch):
    """Drawing of a character: one circle per dot of the matrix.
    The cell is 600 units wide (thousandths of the font size)."""
    dots = _dots(ch)
    s = "600 0 0 -200 600 700 d1\n"
    for col, row in dots:
        s += _circle(100 + 100 * col, 650 - 100 * row, 43)
    return s + ("f\n" if dots else "")


def _background(width, height):
    """Continuous paper: a sprocket-hole strip on each side and green bars."""
    s = ["0.985 0.98 0.955 rg 0 0 %s %s re f\n" % (_n(width), _n(height))]
    s.append("0.88 0.95 0.88 rg\n")
    for band in range(1, height // 36, 2):
        s.append("36 %s %s 36 re f\n" % (_n(height - 36 * (band + 1)), _n(width - 72)))
    s.append("0.72 G 0.5 w [1.5 3] 0 d\n")
    for x in (36, width - 36):
        s.append("%s 0 m %s %s l S\n" % (_n(x), _n(x), _n(height)))
    s.append("[] 0 d 0.4 w 0.70 G 0.84 0.84 0.82 rg\n")
    for k in range(height // 36):
        for x in (18, width - 18):
            s.append(_circle(x, height - 18 - 36 * k, 5.6) + "B\n")
    return "".join(s)


def _string(text):
    return "(" + text.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)") + ")"


def _content(page, x0, height, used):
    """Text of one page. Bold and overstrike are done the way a real printer
    does them: a second pass shifted by half a dot."""
    s = ["/Bg Do\n"] if PAPER else []
    s.append("0.11 0.11 0.17 rg\nBT\n/F1 12 Tf\n")
    for row in sorted(page):
        strikes = []                        # (shift, column, character)
        for col, hits in page[row].items():
            seen = {}
            for ch, bold in hits:
                count, isbold = seen.get(ch, (0, False))
                seen[ch] = (count + 1, isbold or bold)
            for ch, (count, isbold) in seen.items():
                strikes.append((0, col, ch))
                if isbold or count > 1:
                    strikes.append((0.6, col, ch))
        layers = []                         # (shift, {column: character})
        for dx, col, ch in strikes:
            used.add(ch)
            for ldx, cells in layers:
                if ldx == dx and col not in cells:
                    cells[col] = ch
                    break
            else:
                layers.append((dx, {col: ch}))
        y = height - 12 * row - 9.7
        for dx, cells in layers:
            text = "".join(cells.get(c, " ") for c in range(max(cells) + 1))
            s.append("1 0 0 1 %s %s Tm %s Tj\n" % (_n(x0 + dx), _n(y), _string(text)))
    s.append("ET\n")
    return "".join(s)


def _pdf(objects, root, info):
    """Builds the file from {number: (dictionary, data or None)}."""
    parts = [b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n"]
    pos = len(parts[0])
    offsets = {}
    for num in sorted(objects):
        head, data = objects[num]
        offsets[num] = pos
        if data is None:
            body = ("%d 0 obj\n%s\nendobj\n" % (num, head)).encode("latin-1")
        else:
            comp = zlib.compress(data, 9)
            header = head[:-2] + " /Length %d /Filter /FlateDecode >>" % len(comp)
            body = (("%d 0 obj\n%s\nstream\n" % (num, header)).encode("latin-1")
                      + comp + b"\nendstream\nendobj\n")
        parts.append(body)
        pos += len(body)
    total = max(objects) + 1
    xref = ["xref\n0 %d\n0000000000 65535 f \n" % total]
    for num in range(1, total):
        xref.append("%010d 00000 n \n" % offsets[num])
    xref.append("trailer\n<< /Size %d /Root %d 0 R /Info %d 0 R >>\nstartxref\n%d\n%%%%EOF\n"
                % (total, root, info, pos))
    parts.append("".join(xref).encode("latin-1"))
    return b"".join(parts)


CMAP = (b"/CIDInit /ProcSet findresource begin\n12 dict begin\nbegincmap\n"
        b"/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def\n"
        b"/CMapName /Adobe-Identity-UCS def\n/CMapType 2 def\n"
        b"1 begincodespacerange\n<00> <FF>\nendcodespacerange\n"
        b"1 beginbfrange\n<20> <7E> <0020>\nendbfrange\n"
        b"endcmap\nCMapName currentdict /CMap defineresource pop\nend\nend\n")


def make_pdf(data, when=None):
    """Returns (PDF bytes, pages, lines), or None if the data contains
    nothing printable."""
    pages = Printer().feed(data)
    lines = sum(len(p) for p in pages)
    if not lines:
        return None
    when = when or datetime.datetime.now()
    width, height, x0 = (684, 792, 54) if PAPER else (612, 792, 18)

    used = {" "}
    contents = [_content(p, x0, height, used) for p in pages]
    chars = sorted(used)

    obj = {}
    CAT, PAGES, FONT, TOUNI, INFO, BG = 1, 2, 3, 4, 5, 6
    nxt = 7
    procs = {}
    for ch in chars:
        obj[nxt] = ("<< >>", _glyph(ch).encode("latin-1"))
        procs[ch] = nxt
        nxt += 1

    first, last = ord(chars[0]), ord(chars[-1])
    diffs = " ".join("%d /%s" % (ord(c), NAMES[ord(c) - 32]) for c in chars)
    obj[FONT] = (
        "<< /Type /Font /Subtype /Type3 /Name /NABUMatrix "
        "/FontBBox [0 -200 600 700] /FontMatrix [0.001 0 0 0.001 0 0] "
        "/CharProcs << %s >> "
        "/Encoding << /Type /Encoding /Differences [%s] >> "
        "/FirstChar %d /LastChar %d /Widths [%s] "
        "/Resources << /ProcSet [/PDF] >> /ToUnicode %d 0 R >>" % (
            " ".join("/%s %d 0 R" % (NAMES[ord(c) - 32], procs[c]) for c in chars),
            diffs, first, last, " ".join(["600"] * (last - first + 1)), TOUNI),
        None)
    obj[TOUNI] = ("<< >>", CMAP)

    resources = "/Font << /F1 %d 0 R >>" % FONT
    if PAPER:
        resources += " /XObject << /Bg %d 0 R >>" % BG
        obj[BG] = ("<< /Type /XObject /Subtype /Form /BBox [0 0 %d %d] "
                   "/Resources << /ProcSet [/PDF] >> >>" % (width, height),
                   _background(width, height).encode("latin-1"))

    kids = []
    for text in contents:
        obj[nxt] = ("<< >>", text.encode("latin-1"))
        obj[nxt + 1] = (
            "<< /Type /Page /Parent %d 0 R /MediaBox [0 0 %d %d] "
            "/Resources << %s >> /Contents %d 0 R >>" % (PAGES, width, height, resources, nxt),
            None)
        kids.append(nxt + 1)
        nxt += 2

    obj[PAGES] = ("<< /Type /Pages /Count %d /Kids [%s] >>" % (
        len(kids), " ".join("%d 0 R" % h for h in kids)), None)
    obj[CAT] = ("<< /Type /Catalog /Pages %d 0 R >>" % PAGES, None)
    title = TITLE % when.strftime(TITLE_DATE)
    obj[INFO] = ("<< /Title <%s> /Producer (nabu-print) /CreationDate (D:%s) >>" % (
        (b"\xfe\xff" + title.encode("utf-16-be")).hex().upper(),
        when.strftime("%Y%m%d%H%M%S")), None)
    return _pdf(obj, CAT, INFO), len(pages), lines


# ---------------------------------------------------------------------------
# Service
# ---------------------------------------------------------------------------
def lst_path():
    """Location of LST.TXT inside the IA's storage folder."""
    if os.environ.get("NABU_LST"):
        return os.environ["NABU_LST"]
    base = os.path.dirname(read_conf()["NABU_BIN"])
    candidates = [os.path.join(base, "NABU Internet Adapter", "Store"),
                  os.path.join(base, "Store")]
    for folder in candidates:
        if os.path.isdir(folder):
            return os.path.join(folder, "LST.TXT")
    return os.path.join(candidates[0], "LST.TXT")


def read_state():
    """Byte of LST.TXT already printed up to, or None if there is no record."""
    try:
        with open(STATE) as f:
            return int(json.load(f).get("offset", 0))
    except (OSError, ValueError, AttributeError):
        return None


def save_state(offset):
    tmp = STATE + ".part"
    with open(tmp, "w") as f:
        json.dump({"offset": offset}, f)
    os.replace(tmp, STATE)


def save_pdf(data):
    """Converts one print job and saves it in DEST. Returns the file name."""
    now = datetime.datetime.now()
    result = make_pdf(data, now)
    if result is None:
        return None
    pdf, pages, lines = result
    name = "print-%s.pdf" % now.strftime("%Y-%m-%d-%H%M%S")
    target = os.path.join(DEST, name)
    with open(target + ".part", "wb") as f:
        f.write(pdf)
    os.replace(target + ".part", target)
    print("Printout saved: %s (%d page%s, %d line%s)" % (
        name, pages, "" if pages == 1 else "s",
        lines, "" if lines == 1 else "s"), flush=True)
    return name


def service():
    os.makedirs(DEST, exist_ok=True)
    lst = lst_path()
    offset = read_state()
    if offset is None:                      # first run: old output is not reprinted
        try:
            offset = os.path.getsize(lst)
        except OSError:
            offset = 0
        save_state(offset)
    print("Virtual printer watching %s (read up to byte %d)" % (lst, offset),
          flush=True)
    seen_size, since = offset, time.monotonic()
    while True:
        try:
            size = os.path.getsize(lst)
        except OSError:
            size = 0
        if size < offset:                   # the file was emptied or replaced
            offset = seen_size = 0
            save_state(0)
        if size != seen_size:               # text is still coming in
            seen_size, since = size, time.monotonic()
        elif size > offset and time.monotonic() - since >= WAIT:
            try:
                with open(lst, "rb") as f:
                    f.seek(offset)
                    data = f.read(size - offset)
                save_pdf(data)
            except Exception as e:          # one bad job must not stop the service
                print("Could not convert the print job: %s" % e,
                      file=sys.stderr, flush=True)
            offset = size
            save_state(offset)
        time.sleep(1)


if __name__ == "__main__":
    if len(sys.argv) == 3:
        with open(sys.argv[1], "rb") as f:
            r = make_pdf(f.read())
        if r is None:
            sys.exit("Nothing printable in %s" % sys.argv[1])
        with open(sys.argv[2], "wb") as f:
            f.write(r[0])
        print("%s: %d page(s), %d line(s)" % (sys.argv[2], r[1], r[2]))
    elif len(sys.argv) == 1:
        try:
            service()
        except KeyboardInterrupt:
            pass
    else:
        sys.exit("Usage: nabu-print.py [input.txt output.pdf]")
PYEOF
sudo chmod 755 /usr/local/lib/nabu/nabu-print.py
mkdir -p "$PRINT_DIR"

if [[ $ASK_PW -eq 1 ]]; then
  echo "==> Saving the panel password (only its PBKDF2 hash)"
  HASHLINES="$(NABU_PW="$PW1" python3 - <<'PY'
import hashlib, os
s = os.urandom(16)
h = hashlib.pbkdf2_hmac("sha256", os.environ["NABU_PW"].encode(), s, 200000)
print(f"SALT={s.hex()}")
print(f"HASH={h.hex()}")
PY
)"
  unset PW1 PW2
  printf 'PORT=%s\n%s\n' "$PORT" "$HASHLINES" | sudo tee /etc/nabu-web.conf >/dev/null
  sudo chown "$U:$U" /etc/nabu-web.conf
  sudo chmod 600 /etc/nabu-web.conf
else
  # Keeps the password, but updates the port if it changed
  sudo sed -i "s/^PORT=.*/PORT=$PORT/" /etc/nabu-web.conf
fi

echo "==> Installing the web panel"
sudo tee /usr/local/lib/nabu/nabu-web.py >/dev/null <<'PYEOF'
#!/usr/bin/env python3
"""Minimal web panel for the NABU server (standard library only)."""
import base64, glob, hashlib, hmac, html, json, os, re, subprocess, threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

CONF = os.environ.get("NABU_WEB_CONF", "/etc/nabu-web.conf")
IA_CONF = os.environ.get("NABU_IA_CONF", "/etc/nabu-ia.conf")


def load_conf(path):
    c = {}
    try:
        with open(path) as f:
            for line in f:
                if "=" in line:
                    k, v = line.strip().split("=", 1)
                    c[k] = v.strip('"')
    except OSError:
        pass
    return c


C = load_conf(CONF)
IA = load_conf(IA_CONF)
PORT = int(C.get("PORT", "80"))
SALT = bytes.fromhex(C["SALT"])
HASH = bytes.fromhex(C["HASH"])
AUTH_OK = set()            # headers already verified (PBKDF2 is slow on a Pi)
UPD = {"state": "idle", "out": ""}
REALM = "NABU Server"
UNKNOWN = "unknown"
WHEN = "{mo}/{d}/{y} {h}:{mi}:{s}"     # date and time of each printout in the list
BACKUPS = os.environ.get("NABU_BACKUP_DIR", os.path.expanduser("~/backups"))
BACKUP_RE = re.compile(r"nabu-backup-[0-9-]+\.zip")
PRINTS = (os.environ.get("NABU_PRINT_DIR") or IA.get("NABU_PRINT_DIR")
          or os.path.expanduser("~/nabu/printer"))
PRINT_RE = re.compile(r"print-(\d{4})-(\d\d)-(\d\d)-(\d\d)(\d\d)(\d\d)\.pdf")
PRINT_MAX = 50             # printouts listed on the panel (the newest ones)
PAGES = {}                 # name -> (modification time, pages)


def check_auth(header):
    if not header:
        return False
    if header in AUTH_OK:
        return True
    if not header.startswith("Basic "):
        return False
    try:
        user, pw = base64.b64decode(header[6:]).decode().split(":", 1)
    except Exception:
        return False
    h = hashlib.pbkdf2_hmac("sha256", pw.encode(), SALT, 200000)
    if user == "nabu" and hmac.compare_digest(h, HASH):
        AUTH_OK.add(header)
        return True
    return False


def run(cmd, timeout=20):
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return r.returncode, (r.stdout + r.stderr).strip()
    except Exception as e:
        return 1, str(e)


def status():
    _, active = run(["systemctl", "is-active", "nabu-ia"])
    if active not in ("active", "inactive", "failed", "activating", "deactivating"):
        active = UNKNOWN
    _, printer = run(["systemctl", "is-active", "nabu-print"])
    temp = throttled = None
    rc, out = run(["vcgencmd", "measure_temp"])
    if rc == 0:
        temp = out.split("=")[-1]
    rc, out = run(["vcgencmd", "get_throttled"])
    if rc == 0:
        throttled = out.split("=")[-1]
    return {
        "active": active,
        "printer": printer == "active",
        "ttys": sorted(glob.glob("/dev/ttyUSB*")),
        "temp": temp,
        "throttled": throttled,
        "update": UPD["state"],
    }


def prints():
    """Printouts saved by nabu-print, newest first."""
    try:
        names = sorted((n for n in os.listdir(PRINTS) if PRINT_RE.fullmatch(n)),
                       reverse=True)
    except OSError:
        names = []
    items = []
    for name in names[:PRINT_MAX]:
        path = os.path.join(PRINTS, name)
        try:
            st = os.stat(path)
            cached = PAGES.get(name)
            if not cached or cached[0] != st.st_mtime:
                with open(path, "rb") as f:
                    cached = (st.st_mtime, f.read().count(b"/Type /Page "))
                PAGES[name] = cached
        except OSError:
            continue
        y, mo, d, h, mi, s = PRINT_RE.fullmatch(name).groups()
        items.append({"name": name, "when": WHEN.format(y=y, mo=mo, d=d, h=h, mi=mi, s=s),
                      "pages": cached[1], "kb": max(1, round(st.st_size / 1024))})
    return {"items": items, "total": len(names)}


def do_update():
    UPD.update(state="running", out="")
    rc, out = run(["/usr/local/bin/nabu", "update"], timeout=1200)
    UPD.update(state="ok" if rc == 0 else "error", out=out[-4000:])


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def send(self, code, body, ctype="application/json"):
        b = body.encode() if isinstance(body, str) else body
        self.send_response(code)
        self.send_header("Content-Type", ctype + "; charset=utf-8")
        self.send_header("Content-Length", str(len(b)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(b)

    def send_file(self, folder, name, pattern, ctype, disposition):
        path = os.path.join(folder, name)
        if not pattern.fullmatch(name) or not os.path.isfile(path):
            return self.send(404, "{}")
        with open(path, "rb") as f:
            data = f.read()
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Disposition", f'{disposition}; filename="{name}"')
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def authorized(self):
        if check_auth(self.headers.get("Authorization")):
            return True
        self.send_response(401)
        self.send_header("WWW-Authenticate", f'Basic realm="{REALM}"')
        self.send_header("Content-Length", "0")
        self.end_headers()
        return False

    def do_GET(self):
        if not self.authorized():
            return
        p = self.path.split("?")[0]
        if p == "/":
            self.send(200, PAGE, "text/html")
        elif p == "/api/status":
            self.send(200, json.dumps(status()))
        elif p == "/api/screen":
            _, out = run(["tmux", "-L", "nabu", "capture-pane", "-p", "-t", "nabu"])
            self.send(200, json.dumps({"text": out}))
        elif p == "/api/log":
            _, out = run(["/usr/local/bin/nabu", "list"])
            self.send(200, json.dumps({"text": out}))
        elif p == "/api/update":
            self.send(200, json.dumps(UPD))
        elif p == "/api/prints":
            self.send(200, json.dumps(prints()))
        elif p.startswith("/api/print/"):
            self.send_file(PRINTS, p.rsplit("/", 1)[-1], PRINT_RE,
                           "application/pdf", "inline")
        elif p.startswith("/api/backup/"):
            self.send_file(BACKUPS, p.rsplit("/", 1)[-1], BACKUP_RE,
                           "application/zip", "attachment")
        else:
            self.send(404, "{}")

    def do_POST(self):
        if not self.authorized():
            return
        if self.path != "/api/action":
            return self.send(404, "{}")
        n = int(self.headers.get("Content-Length") or 0)
        try:
            action = json.loads(self.rfile.read(n) or b"{}").get("action")
        except Exception:
            action = None
        if action in ("start", "stop", "restart"):
            if action != "stop":
                run(["sudo", "-n", "systemctl", "reset-failed", "nabu-ia"])
            rc, out = run(["sudo", "-n", "systemctl", action, "nabu-ia"], 60)
            self.send(200 if rc == 0 else 500, json.dumps({"ok": rc == 0, "out": out}))
        elif action == "backup":
            rc, out = run(["python3", "/usr/local/lib/nabu/nabu-backup.py"], 300)
            m = re.search(r"nabu-backup-[0-9-]+\.zip", out)
            ok = rc == 0 and m is not None
            self.send(200 if ok else 500,
                      json.dumps({"ok": ok, "file": m.group(0) if m else "", "out": out}))
        elif action == "update":
            if UPD["state"] == "running":
                return self.send(409, json.dumps(
                    {"ok": False, "out": "An update is already in progress."}))
            threading.Thread(target=do_update, daemon=True).start()
            self.send(202, json.dumps({"ok": True}))
        else:
            self.send(400, json.dumps({"ok": False, "out": "Unknown action."}))


PAGE = r"""<!doctype html>
<html lang="en"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="theme-color" content="#001233">
<title>NABU Server</title>
<style>
:root{--bg:#001233;--card:#0b1f4a;--line:#1d3570;--fg:#e8eefc;--dim:#93a4cc;
--ok:#3ddc84;--warn:#ffc857;--bad:#ff6b6b;--acc:#4ea8ff}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);
font:16px/1.4 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}
main{max-width:640px;margin:0 auto;padding:16px}
h1{font-size:1.3rem;margin:4px 0 16px;letter-spacing:.04em}
h1 span{color:var(--acc)}
h2{font-size:.8rem;margin:0 0 6px;color:var(--dim);font-weight:600;
letter-spacing:.08em;text-transform:uppercase}
.card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:14px;margin-bottom:14px}
.grid{display:grid;grid-template-columns:1fr 1fr;gap:10px}
.item small{display:block;color:var(--dim);font-size:.78rem}
.item b{font-size:1.05rem}
.dot{display:inline-block;width:10px;height:10px;border-radius:50%;margin-right:6px;background:var(--dim)}
.ok .dot{background:var(--ok)} .warn .dot{background:var(--warn)} .bad .dot{background:var(--bad)}
.btns{display:grid;grid-template-columns:1fr 1fr;gap:10px}
button{font:inherit;color:var(--fg);background:#163063;border:1px solid var(--line);
border-radius:10px;padding:12px;cursor:pointer}
button:active{transform:scale(.98)}
button.main{background:var(--acc);color:#001233;font-weight:600}
button:disabled{opacity:.5}
.tabs{display:flex;gap:8px;margin-bottom:10px}
.tabs button{flex:1;padding:8px}
.tabs button.on{border-color:var(--acc);color:var(--acc)}
pre{margin:0;background:#000a1f;border-radius:8px;padding:10px;overflow:auto;
font:12px/1.35 ui-monospace,"DejaVu Sans Mono",monospace;max-height:55vh;white-space:pre}
#msg{min-height:1.4em;color:var(--dim);font-size:.9rem;margin-top:10px}
.plist{list-style:none;margin:0;padding:0;max-height:40vh;overflow:auto}
.plist li{display:flex;justify-content:space-between;align-items:baseline;gap:12px;
padding:10px 0;border-top:1px solid var(--line)}
.plist li:first-child{border-top:0}
.plist a{color:var(--acc);text-decoration:none;font-weight:600;font-variant-numeric:tabular-nums}
.plist small{color:var(--dim);font-size:.82rem;white-space:nowrap}
.plist .empty{color:var(--dim);font-size:.9rem}
footer{color:var(--dim);font-size:.78rem;text-align:center;padding:2px 0 14px}
footer a{color:inherit}
</style></head><body><main>
<h1><span>NABU</span> Server</h1>

<div class="card"><div class="grid">
<div class="item" id="s-svc"><small>Internet Adapter</small><b><span class="dot"></span><span>…</span></b></div>
<div class="item" id="s-tty"><small>RS422 adapter</small><b><span class="dot"></span><span>…</span></b></div>
<div class="item" id="s-temp"><small>Temperature</small><b><span class="dot"></span><span>…</span></b></div>
<div class="item" id="s-pwr"><small>Power</small><b><span class="dot"></span><span>…</span></b></div>
</div></div>

<div class="card">
<div class="btns">
<button class="main" onclick="act('restart',T.restarting)">Restart</button>
<button id="b-toggle" onclick="toggle()">Stop</button>
<button onclick="backup()" id="b-bak">Backup</button>
<button onclick="update()" id="b-upd">Update IA</button>
</div>
<div id="msg"></div>
</div>

<div class="card">
<h2>Printouts</h2>
<ul class="plist" id="prints"><li class="empty">…</li></ul>
</div>

<div class="card">
<div class="tabs">
<button id="t-screen" class="on" onclick="tab('screen')">Screen</button>
<button id="t-log" onclick="tab('log')">Log</button>
<button onclick="loadView()" title="Refresh">↻</button>
</div>
<pre id="view">…</pre>
</div>
<footer>@@FOOTER@@</footer>
</main>
<script>
const T={
  active:'Running', inactive:'Stopped', failed:'Failed', activating:'Starting',
  deactivating:'Stopping',
  notDetected:'Not detected', powerOk:'OK', powerBad:'Problems',
  stop:'Stop', start:'Start',
  restarting:'Restarting…', stopping:'Stopping…', starting:'Starting…',
  confirmStop:'Stop the Internet Adapter?',
  done:'Done.', error:'Error: ', noConn:'Connection error.', noPi:'Cannot reach the Pi.',
  updating:'Updating… this may take a few minutes.',
  confirmUpdate:'Download and install the latest Internet Adapter? A backup is made first.',
  updateOk:'Update complete.', updateFail:'The update failed (see Log).',
  backingUp:'Creating backup…', backupOk:'Backup created: ', downloading:'. Downloading…',
  backupFail:'Could not create the backup: ',
  empty:'(empty)', loadFail:'Could not load.',
  printerOff:'The virtual printer is not running.',
  noPrints:'No printouts yet. Try LPRINT from MBASIC.',
  page:' page', pages:' pages',
  older:n=>'There are '+n+' older ones in the printouts folder.'
};
let view='screen', active='', printer=true, printsKey='';
const $=id=>document.getElementById(id);
async function api(p,opt){const r=await fetch(p,opt);return r.json();}
function set(id,cls,txt){const e=$(id);e.className='item '+cls;e.querySelector('b span:last-child').textContent=txt;}
function msg(t){$('msg').textContent=t||'';}
function post(a){return api('/api/action',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({action:a})});}
async function refresh(){
  try{
    const s=await api('/api/status'); active=s.active; printer=s.printer;
    set('s-svc', s.active==='active'?'ok':(s.active==='activating'?'warn':'bad'), T[s.active]||s.active);
    set('s-tty', s.ttys.length?'ok':'bad', s.ttys.length?s.ttys.join(', ').replace(/\/dev\//g,''):T.notDetected);
    if(s.temp){const t=parseFloat(s.temp);set('s-temp',t<70?'ok':(t<80?'warn':'bad'),s.temp.replace("'C"," °C"));}
    else set('s-temp','','—');
    if(s.throttled) set('s-pwr', s.throttled==='0x0'?'ok':'bad', s.throttled==='0x0'?T.powerOk:T.powerBad+' ('+s.throttled+')');
    else set('s-pwr','','—');
    $('b-toggle').textContent = s.active==='active'?T.stop:T.start;
    $('b-upd').disabled = s.update==='running';
    if(s.update==='running') msg(T.updating);
  }catch(e){msg(T.noPi);}
  loadPrints();
}
async function act(a,t){
  msg(t);
  try{const r=await post(a); msg(r.ok?T.done:T.error+r.out);}catch(e){msg(T.noConn);}
  setTimeout(()=>{refresh();loadView();},1500);
}
function toggle(){ active==='active' ? (confirm(T.confirmStop)&&act('stop',T.stopping)) : act('start',T.starting); }
async function backup(){
  $('b-bak').disabled=true; msg(T.backingUp);
  try{
    const r=await post('backup');
    if(r.ok){ msg(T.backupOk+r.file+T.downloading); location.href='/api/backup/'+encodeURIComponent(r.file); }
    else msg(T.backupFail+r.out);
  }catch(e){ msg(T.noConn); }
  $('b-bak').disabled=false;
}
async function update(){
  if(!confirm(T.confirmUpdate))return;
  await post('update');
  $('b-upd').disabled=true; msg(T.updating);
  const poll=setInterval(async()=>{
    const u=await api('/api/update');
    if(u.state!=='running'){clearInterval(poll);
      msg(u.state==='ok'?T.updateOk:T.updateFail);
      $('view').textContent=u.out; refresh();}
  },3000);
}
function tab(v){view=v;$('t-screen').classList.toggle('on',v==='screen');$('t-log').classList.toggle('on',v==='log');loadView();}
async function loadView(){
  try{const r=await api(view==='screen'?'/api/screen':'/api/log');$('view').textContent=r.text||T.empty;}
  catch(e){$('view').textContent=T.loadFail;}
}
async function loadPrints(){
  let r;
  try{ r=await api('/api/prints'); }catch(e){ return; }
  const key=JSON.stringify(r)+printer;
  if(key===printsKey) return;
  printsKey=key;
  const ul=$('prints'); ul.textContent='';
  const note=t=>{const li=document.createElement('li');li.className='empty';li.textContent=t;ul.appendChild(li);};
  if(!printer) note(T.printerOff);
  if(!r.items.length && printer) note(T.noPrints);
  for(const p of r.items){
    const li=document.createElement('li'), a=document.createElement('a'), s=document.createElement('small');
    a.href='/api/print/'+encodeURIComponent(p.name); a.target='_blank'; a.rel='noopener'; a.textContent=p.when;
    s.textContent=p.pages+(p.pages===1?T.page:T.pages)+' · '+p.kb+' KB';
    li.appendChild(a); li.appendChild(s); ul.appendChild(li);
  }
  if(r.total>r.items.length) note(T.older(r.total-r.items.length));
}
refresh(); loadView();
setInterval(refresh,10000);
setInterval(()=>{ if(view==='screen') loadView(); },5000);
</script></body></html>"""


def footer():
    """Panel footer: NABU Setup version and date, linking to the repository."""
    version = IA.get("NABU_SETUP_VERSION")
    if not version:
        return ""
    text = html.escape("NABU Setup %s · %s" % (version, IA.get("NABU_SETUP_DATE", "")))
    repo = IA.get("NABU_SETUP_REPO", "")
    if repo.startswith("https://"):
        return '<a href="%s" target="_blank" rel="noopener">%s</a>' % (html.escape(repo), text)
    return text


PAGE = PAGE.replace("@@FOOTER@@", footer())


if __name__ == "__main__":
    print(f"NABU panel listening on port {PORT}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
PYEOF
sudo chmod 755 /usr/local/lib/nabu/nabu-web.py

echo "==> Creating the nabu-web systemd service"
sudo tee /etc/systemd/system/nabu-web.service >/dev/null <<EOF
[Unit]
Description=NABU server web panel
After=network-online.target
Wants=network-online.target

[Service]
User=$U
# The only extra privilege: binding ports below 1024 (the panel uses port 80).
# No CapabilityBoundingSet: the panel needs sudo to control nabu-ia.
AmbientCapabilities=CAP_NET_BIND_SERVICE
ExecStart=/usr/bin/python3 /usr/local/lib/nabu/nabu-web.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

echo "==> Creating the nabu-print systemd service"
sudo tee /etc/systemd/system/nabu-print.service >/dev/null <<EOF
[Unit]
Description=NABU server virtual printer (LST.TXT to PDF)

[Service]
User=$U
ExecStart=/usr/bin/python3 /usr/local/lib/nabu/nabu-print.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable nabu-ia nabu-web nabu-print
sudo systemctl restart nabu-web nabu-print

IP="$(hostname -I | awk '{print $1}')"
echo
if [[ $FIRST -eq 1 ]]; then
  echo "Installation complete. Reboot the Pi so the new permissions take effect:"
  echo "    sudo reboot"
  echo
  echo "After that:"
  echo "  - Over SSH:   nabu         (the first time, choose /dev/ttyUSB0 in Settings)"
else
  echo "NABU Setup $NABU_SETUP_VERSION applied. There is no need to reboot the Pi or restart the Internet Adapter."
  echo
  echo "  - Over SSH:   nabu"
fi
echo "  - Web panel:  http://$(hostname).local   or   http://$IP"
echo "                user: nabu"
echo "  - Printer:    whatever you print from Cloud CP/M (LST:) shows up as a PDF"
echo "                on the panel and in $PRINT_DIR"
echo "  - Help:       nabu help"
echo "  - Manual:     $NABU_SETUP_REPO"
