#!/usr/bin/env bash
# NABU Setup — servidor NABU minimalista para Raspberry Pi (Raspberry Pi OS Lite)
# Versión 1.3.0 · publicada el 2026-10-05 · edición en español
#
# Retro Informática Paraguay — https://www.youtube.com/@retroinfopy
# Repositorio y manual de usuario: https://github.com/czayas/nabu-setup
#
# Copyright (c) 2026, Retro Informática Paraguay
# Licencia BSD de 2 cláusulas: consulta el archivo LICENSE del repositorio
# SPDX-License-Identifier: BSD-2-Clause
#
# Qué hace:
#   - Instala tmux/unzip/wget/python3 y da a tu usuario acceso al puerto serie
#   - Descarga el NABU Internet Adapter oficial (nabu.ca) para tu arquitectura
#   - Lo deja en ejecución como servicio systemd dentro de una sesión tmux:
#     arranca solo con la Pi y puedes entrar a su interfaz por SSH
#   - Instala el comando de administración `nabu`
#   - Instala un panel web liviano (puerto 80: http://nabu.local) con contraseña
#   - Instala la impresora virtual: lo que la NABU manda a LST: desde Cloud CP/M
#     queda como PDF en ~/nabu/printer y se ve desde el panel
#
# Uso (en la Pi, con tu usuario normal, NO con sudo):
#   bash nabu-setup-es.sh
# Se puede volver a ejecutar sin problemas (por ejemplo, para cambiar la
# contraseña del panel o aplicar una versión nueva de este script). Si el
# Internet Adapter ya está instalado, no lo vuelve a descargar ni lo reinicia.
#
# NABU Setup es un proyecto independiente: no está afiliado a nabu.ca ni al
# autor del NABU Internet Adapter.
set -euo pipefail

NABU_SETUP_VERSION="1.3.0"
NABU_SETUP_DATE="2026-10-05"
NABU_SETUP_LANG="es"
NABU_SETUP_REPO="https://github.com/czayas/nabu-setup"

case "${1:-}" in
  "") ;;
  -v|--version)
    echo "NABU Setup $NABU_SETUP_VERSION ($NABU_SETUP_DATE)"
    exit 0 ;;
  -h|--help)
    cat <<TXT
NABU Setup $NABU_SETUP_VERSION ($NABU_SETUP_DATE)
Instala y configura un servidor NABU en una Raspberry Pi.

Uso: bash $(basename "$0") [--version | --help]

Sin opciones, instala o actualiza el servidor. Ejecútalo con tu usuario
normal; el script usa sudo cuando lo necesita.
Manual de usuario: $NABU_SETUP_REPO
TXT
    exit 0 ;;
  *)
    echo "Opción desconocida: $1 (prueba --help)"
    exit 1 ;;
esac

if [[ $EUID -eq 0 ]]; then
  echo "Ejecútalo con tu usuario normal (el script usa sudo cuando lo necesita)."
  exit 1
fi

echo "NABU Setup $NABU_SETUP_VERSION ($NABU_SETUP_DATE)"
echo

U="$USER"
DIR="$HOME/nabu"
PRINT_DIR="$DIR/printer"
BACKUP_DIR="$DIR/backups"
PORT=80

# El Internet Adapter está hecho en .NET, que no funciona en procesadores ARMv6
if [[ "$(uname -m)" == armv6l ]]; then
  echo "Esta Raspberry Pi tiene un procesador ARMv6 (Pi 1, Zero o Zero W)."
  echo "El Internet Adapter necesita ARMv7 o superior: Pi 2, 3, 4, 5 o Zero 2 W."
  exit 1
fi

# Se elige el paquete según el sistema instalado (32 o 64 bits), no el procesador
case "$(dpkg --print-architecture 2>/dev/null || uname -m)" in
  arm64|aarch64)  ZIP=linux-arm64.zip ;;
  armhf|armv7l)   ZIP=linux-arm.zip ;;
  amd64|x86_64)   ZIP=linux-x64.zip ;;
  *) echo "Arquitectura no soportada: $(uname -m)"; exit 1 ;;
esac
URL="https://cloud.nabu.ca/$ZIP"

# ---------------------------------------------------------------------------
# Contraseña del panel web (se pide al principio para no interrumpir después)
# ---------------------------------------------------------------------------
ASK_PW=1
if [[ -f /etc/nabu-web.conf ]]; then
  read -rp "El panel web ya tiene contraseña. ¿Cambiarla? [s/N] " r
  [[ "${r,,}" == s* ]] || ASK_PW=0
fi
if [[ $ASK_PW -eq 1 ]]; then
  while true; do
    read -rsp "Contraseña para el panel web (usuario: nabu): " PW1; echo
    read -rsp "Repítela: " PW2; echo
    if [[ -n "$PW1" && "$PW1" == "$PW2" ]]; then break; fi
    echo "No coinciden o está vacía. Inténtalo de nuevo."
  done
fi

PACKAGES="tmux unzip wget python3"
if dpkg -s $PACKAGES >/dev/null 2>&1; then
  echo "==> Paquetes ya instalados"
else
  echo "==> Instalando paquetes"
  sudo apt-get update
  sudo apt-get install -y $PACKAGES
fi

echo "==> Dando a $U acceso al puerto serie y al registro del sistema"
sudo usermod -aG dialout,systemd-journal "$U"

mkdir -p "$DIR"
BINPATH="$(find "$DIR" -maxdepth 3 -type f -name 'NABU-Internet*Adapter-84' | head -n1 || true)"
if [[ -n "$BINPATH" ]]; then
  FIRST=0
  echo "==> El Internet Adapter ya está instalado; no se vuelve a descargar"
  echo "    (para actualizarlo: nabu update)"
else
  FIRST=1
  echo "==> Descargando Internet Adapter ($ZIP)"
  wget -q --show-progress -O "/tmp/$ZIP" "$URL"
  unzip -o -q "/tmp/$ZIP" -d "$DIR"
  rm -f "/tmp/$ZIP"
  BINPATH="$(find "$DIR" -maxdepth 3 -type f -name 'NABU-Internet*Adapter-84' | head -n1 || true)"
  if [[ -z "$BINPATH" ]]; then
    echo "No se encontró el programa del Internet Adapter dentro del ZIP. Revisa $DIR"
    exit 1
  fi
fi
chmod +x "$BINPATH"
BINDIR="$(dirname "$BINPATH")"
echo "    Programa: $BINPATH"

# El IA busca "libdl.so" (sin versión), que no existe desde glibc 2.34.
# Sin este enlace, la interfaz de texto no arranca (error en Curses.endwin).
echo "==> Enlazando libdl.so en la carpeta del IA"
LIBDL="$(/sbin/ldconfig -p | awk '/libdl\.so\.2 /{print $NF; exit}')"
if [[ -n "$LIBDL" ]]; then
  ln -sfn "$LIBDL" "$BINDIR/libdl.so"
  echo "    libdl.so -> $LIBDL"
else
  echo "    AVISO: no se encontró libdl.so.2; el IA podría no arrancar."
fi

echo "==> Configuración de tmux para el IA"
cat > "$DIR/tmux.conf" <<'EOF'
set -g default-terminal "xterm-256color"
set -g mouse on
set -g status-style "bg=colour19,fg=white"
set -g status-left " NABU IA "
set -g status-right " Ctrl-b d = salir sin cerrar "
set -g status-right-length 40
EOF

echo "==> Guardando /etc/nabu-ia.conf"
sudo tee /etc/nabu-ia.conf >/dev/null <<EOF
NABU_DIR="$DIR"
NABU_BIN="$BINPATH"
NABU_ZIP="$ZIP"
NABU_URL="$URL"
NABU_PORT="$PORT"
NABU_PRINT_DIR="$PRINT_DIR"
NABU_BACKUP_DIR="$BACKUP_DIR"
NABU_SETUP_VERSION="$NABU_SETUP_VERSION"
NABU_SETUP_DATE="$NABU_SETUP_DATE"
NABU_SETUP_LANG="$NABU_SETUP_LANG"
NABU_SETUP_REPO="$NABU_SETUP_REPO"
EOF

echo "==> Creando servicio systemd nabu-ia"
sudo tee /etc/systemd/system/nabu-ia.service >/dev/null <<EOF
[Unit]
Description=NABU Internet Adapter (en sesión tmux)
After=network-online.target
Wants=network-online.target
# Si el IA falla 10 veces en 5 minutos, systemd deja de reintentar
StartLimitIntervalSec=300
StartLimitBurst=10

[Service]
Type=forking
User=$U
WorkingDirectory=$BINDIR
Environment=TERM=xterm-256color
# Los errores del IA (stderr) quedan en ia-error.log sin afectar la pantalla
ExecStart=/usr/bin/tmux -L nabu -f $DIR/tmux.conf new-session -d -s nabu -x 100 -y 35 "exec $BINPATH 2>>$DIR/ia-error.log"
ExecStop=-/usr/bin/tmux -L nabu kill-server
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

echo "==> Permitiendo controlar el servicio y apagar la Pi sin contraseña (para el panel web)"
SYSTEMCTL="$(command -v systemctl)"
sudo tee /etc/sudoers.d/nabu >/dev/null <<EOF
$U ALL=(root) NOPASSWD: $SYSTEMCTL start nabu-ia, $SYSTEMCTL stop nabu-ia, $SYSTEMCTL restart nabu-ia, $SYSTEMCTL reset-failed nabu-ia, $SYSTEMCTL poweroff
EOF
sudo chmod 440 /etc/sudoers.d/nabu
sudo visudo -cf /etc/sudoers.d/nabu >/dev/null

echo "==> Instalando comando de administración: nabu"
sudo tee /usr/local/bin/nabu >/dev/null <<'EOF'
#!/usr/bin/env bash
# nabu — administración del servidor NABU (parte de NABU Setup)
source /etc/nabu-ia.conf
PRINT_DIR="${NABU_PRINT_DIR:-$NABU_DIR/printer}"
BACKUP_DIR="${NABU_BACKUP_DIR:-$NABU_DIR/backups}"
VERSION="NABU Setup ${NABU_SETUP_VERSION:-?} (${NABU_SETUP_DATE:-?})"

usage() {
  cat <<TXT
$VERSION
Uso: nabu [comando]

  nabu            Entra a la interfaz del Internet Adapter
                  (para salir sin cerrarlo: Ctrl-b y después d)
  nabu status     Estado del servicio, adaptador RS422, impresora virtual,
                  temperatura y alimentación
  nabu list       Últimas líneas del registro del servicio y errores del IA
  nabu start      Inicia el Internet Adapter
  nabu stop       Detiene el Internet Adapter
  nabu restart    Reinicia el Internet Adapter
  nabu backup     Guarda un backup .zip de CP/M y la configuración en
                  ${BACKUP_DIR/#$HOME/\~} (se conservan los últimos 5)
  nabu update     Descarga la última versión del IA (hace un backup antes)
  nabu setup      Descarga e instala la última versión publicada de NABU Setup
  nabu poweroff   Apaga la Pi de forma segura; después puedes cortar la corriente
  nabu version    Muestra la versión y la fecha de NABU Setup
  nabu help       Muestra esta ayuda

Panel web: http://$(hostname).local$([[ "${NABU_PORT:-80}" != 80 ]] && echo ":$NABU_PORT")  (usuario: nabu)
Impresiones: lo que la NABU manda a LST: queda como PDF en ${PRINT_DIR/#$HOME/\~}
TXT
}

case "${1:-}" in
  "")
    if ! tmux -L nabu has-session -t nabu 2>/dev/null; then
      echo "El Internet Adapter no está en ejecución. Prueba: nabu start"
      exit 1
    fi
    exec tmux -L nabu attach -t nabu ;;
  status)
    systemctl --no-pager --lines=0 status nabu-ia
    echo
    ls -l /dev/ttyUSB* 2>/dev/null || echo "Adaptador RS422: NO detectado"
    if [[ "$(systemctl is-active nabu-print 2>/dev/null)" == active ]]; then
      n=$(find "$PRINT_DIR" -maxdepth 1 -name 'print-*.pdf' 2>/dev/null | wc -l)
      echo "Impresora virtual: activa (impresiones en ${PRINT_DIR/#$HOME/\~}: $n)"
    else
      echo "Impresora virtual: detenida"
    fi
    if command -v vcgencmd >/dev/null; then
      vcgencmd measure_temp
      t=$(vcgencmd get_throttled | cut -d= -f2)
      if [[ "$t" == "0x0" ]]; then echo "Alimentación: OK";
      else echo "Alimentación: PROBLEMAS (throttled=$t, revisa la fuente)"; fi
    fi ;;
  list)
    journalctl -u nabu-ia -n 30 --no-pager
    if [[ -s "$NABU_DIR/ia-error.log" ]]; then
      echo
      echo "--- Errores del Internet Adapter ($NABU_DIR/ia-error.log) ---"
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
    echo "Descargando $NABU_URL"
    wget -q --show-progress --progress=dot:giga -O "$tmp" "$NABU_URL"
    python3 /usr/local/lib/nabu/nabu-backup.py
    sudo systemctl stop nabu-ia
    unzip -o -q "$tmp" -d "$NABU_DIR"
    chmod +x "$NABU_BIN"
    rm -f "$tmp"
    sudo systemctl start nabu-ia
    echo "Listo. El Internet Adapter se actualizó y volvió a arrancar." ;;
  setup)
    lang="${NABU_SETUP_LANG:-es}"
    url="${NABU_SETUP_REPO/github.com/raw.githubusercontent.com}/main/nabu-setup-$lang.sh"
    tmp="$(mktemp -d)/nabu-setup-$lang.sh"
    echo "Descargando $url"
    if ! wget -q -O "$tmp" "$url"; then
      echo "No se pudo descargar. Revisa la conexión a Internet de la Pi."
      exit 1
    fi
    # La versión se lee del archivo, sin ejecutarlo
    want="$(sed -n 's/^NABU_SETUP_VERSION="\(.*\)"$/\1/p' "$tmp" | head -n1)"
    date="$(sed -n 's/^NABU_SETUP_DATE="\(.*\)"$/\1/p' "$tmp" | head -n1)"
    if [[ -z "$want" ]]; then
      echo "El archivo descargado no es NABU Setup. No se instaló nada."
      exit 1
    fi
    have="${NABU_SETUP_VERSION:-0}"
    echo "Instalada: $VERSION"
    echo "Publicada: NABU Setup $want ($date)"
    if [[ "$want" == "$have" ]]; then
      read -rp "Ya tienes la última versión. ¿Instalarla de nuevo? [s/N] " r
      [[ "${r,,}" == s* ]] || exit 0
    elif [[ "$(printf '%s\n%s\n' "$want" "$have" | sort -V | tail -n1)" == "$have" ]]; then
      read -rp "La versión instalada es más nueva que la publicada. ¿Instalar la publicada? [s/N] " r
      [[ "${r,,}" == s* ]] || exit 0
    fi
    echo
    exec bash "$tmp" ;;
  poweroff)
    echo "Apagando la Pi. Espera a que el LED verde deje de parpadear antes de cortar la corriente."
    exec sudo systemctl poweroff ;;
  version)
    echo "$VERSION"
    [[ -n "${NABU_SETUP_REPO:-}" ]] && echo "$NABU_SETUP_REPO"
    exit 0 ;;
  help)
    usage ;;
  *)
    echo "Comando desconocido: $1"
    echo
    usage
    exit 1 ;;
esac
EOF
sudo chmod +x /usr/local/bin/nabu

echo "==> Instalando herramienta de backup"
sudo mkdir -p /usr/local/lib/nabu
sudo tee /usr/local/lib/nabu/nabu-backup.py >/dev/null <<'PYEOF'
#!/usr/bin/env python3
"""Crea un backup .zip de los datos del Internet Adapter: unidades de
CP/M (Store/), programas locales y configuración. Excluye el programa, la
caché, los logs, las impresiones y los backups anteriores.
Guarda en ~/nabu/backups y conserva solo los últimos KEEP archivos."""
import datetime, glob, os, sys, zipfile

KEEP = 5
CONF = os.environ.get("NABU_IA_CONF", "/etc/nabu-ia.conf")
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
    # Las impresiones y los backups quedan fuera aunque estén dentro de la carpeta
    prints = os.path.abspath(c.get("NABU_PRINT_DIR") or os.path.join(base, "printer"))
    dest = os.path.abspath(os.environ.get("NABU_BACKUP_DIR") or c.get("NABU_BACKUP_DIR")
                           or os.path.join(base, "backups"))
    excl = EXCL_FILES | {os.path.basename(binpath)}
    os.makedirs(dest, exist_ok=True)

    stamp = datetime.datetime.now().strftime("%Y-%m-%d-%H%M")
    out = os.path.join(dest, f"nabu-backup-{stamp}.zip")
    if os.path.exists(out):  # dos backups en el mismo minuto
        out = os.path.join(dest, f"nabu-backup-{stamp}{datetime.datetime.now():%S}.zip")
    tmp = out + ".part"

    n = 0
    with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as z:
        for root, dirs, files in os.walk(base):
            dirs[:] = sorted(d for d in dirs if d not in EXCL_DIRS
                             and os.path.abspath(os.path.join(root, d)) not in (prints, dest))
            rel_root = os.path.relpath(root, base)
            # carpetas vacías (unidades y áreas de usuario sin archivos)
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

    olds = sorted(glob.glob(os.path.join(dest, "nabu-backup-*.zip")))
    for old in olds[:-KEEP]:
        os.remove(old)

    size = os.path.getsize(out) / 1024
    print(f"Backup creado: {out} ({n} archivos, {size:.0f} KB)")
    print(f"Backups guardados en {dest}: {min(len(olds), KEEP)} (máximo {KEEP})")
    return out


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"Error al crear el backup: {e}", file=sys.stderr)
        sys.exit(1)
PYEOF
sudo chmod 755 /usr/local/lib/nabu/nabu-backup.py
mkdir -p "$BACKUP_DIR"
# Hasta la versión 1.2.0 los backups se guardaban en ~/backups: se mudan
if compgen -G "$HOME/backups/nabu-backup-*.zip" >/dev/null; then
  echo "==> Moviendo los backups de ~/backups a ${BACKUP_DIR/#$HOME/\~}"
  mv -n "$HOME"/backups/nabu-backup-*.zip "$BACKUP_DIR"/
  rmdir "$HOME/backups" 2>/dev/null || true
fi

echo "==> Instalando impresora virtual (LST.TXT a PDF)"
sudo tee /usr/local/lib/nabu/nabu-print.py >/dev/null <<'PYEOF'
#!/usr/bin/env python3
"""Impresora virtual del servidor NABU.

Vigila el archivo LST.TXT, donde el Internet Adapter guarda lo que la NABU
manda a la impresora (dispositivo LST: de Cloud CP/M). Cuando el archivo deja
de crecer durante WAIT segundos, toma lo nuevo y genera un PDF en la carpeta
de impresiones (NABU_PRINT_DIR en /etc/nabu-ia.conf; normalmente
~/nabu/printer). La letra (matriz de puntos o calidad carta) y el papel
(formulario continuo o en blanco) se eligen en el panel web.

Junto a cada PDF guarda los datos tal como llegaron (.lst), para rehacerlo
más tarde con otra letra u otro papel.

Solo biblioteca estándar. No modifica LST.TXT: recuerda hasta dónde leyó.

También convierte un archivo suelto o rehace una impresión guardada:
    python3 nabu-print.py entrada.txt salida.pdf
    python3 nabu-print.py --reprint print-AAAA-MM-DD-HHMMSS.pdf
"""
import base64, datetime, json, os, re, sys, time, unicodedata, zlib

CONF = os.environ.get("NABU_IA_CONF", "/etc/nabu-ia.conf")

WAIT = 5       # segundos sin datos nuevos para dar por terminada una impresión
COLS = 80      # columnas por línea (10 caracteres por pulgada)
LPP = 66       # líneas por página (6 líneas por pulgada, hoja de 11 pulgadas)

TITLE = "Impresión NABU %s"        # título del PDF; lleva la fecha y la hora
TITLE_DATE = "%d/%m/%Y %H:%M:%S"


def read_conf():
    """Lee /etc/nabu-ia.conf (líneas CLAVE="valor"). Si no existe, {}."""
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
SETTINGS = os.path.join(DEST, ".settings.json")
NAME_RE = re.compile(r"print-(\d{4})-(\d\d)-(\d\d)-(\d\d)(\d\d)(\d\d)\.pdf")

# Letras y papeles que se eligen en el panel web. El primero de cada lista es
# el que vale mientras no se elija otro.
FONTS = ("matrix", "serif", "sans")   # matriz de puntos; calidad carta con y sin remates
PAPERS = ("fanfold", "plain")         # formulario continuo; hoja carta en blanco

# Fuente de matriz de 5x7 puntos, caracteres 0x20 a 0x7E. Cinco bytes por
# carácter, uno por columna; el bit 0 es la fila de arriba.
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

# Letras con trazo descendente, dibujadas en 9 filas en lugar de 7.
DESCENDERS = {
    "g": (".....", ".....", ".####", "#...#", "#...#", "#...#", ".####", "....#", ".###."),
    "j": ("....#", ".....", "...##", "....#", "....#", "....#", "....#", "#...#", ".###."),
    "p": (".....", ".....", "####.", "#...#", "#...#", "#...#", "####.", "#....", "#...."),
    "q": (".....", ".....", ".####", "#...#", "#...#", "#...#", ".####", "....#", "....#"),
    "y": (".....", ".....", "#...#", "#...#", "#...#", "#...#", ".####", "....#", ".###."),
}

# Marcas que, impresas sobre una letra, forman una letra acentuada. Es el
# recurso de WordStar (^PH) y de las máquinas de escribir: la letra y, encima,
# el acento. Se dibujan como una sola letra, y así quedan también en el texto
# del PDF. Dos filas de puntos por marca, de arriba hacia abajo.
ACCENTS = {
    "'": ("\u0301", ("...#.", "..#..")),      # acento agudo
    "`": ("\u0300", (".#...", "..#..")),      # acento grave
    "^": ("\u0302", ("..#..", ".#.#.")),      # circunflejo
    "~": ("\u0303", (".#..#", "#.##.")),      # tilde de la eñe
    '"': ("\u0308", (".#.#.", ".....")),      # diéresis
    ",": ("\u0327", ("..#..", ".#...")),      # cedilla (va debajo)
}

# Mayúsculas de seis filas, para dejar lugar al acento encima.
TALL = {
    "A": (".###.", "#...#", "#...#", "#####", "#...#", "#...#"),
    "E": ("#####", "#....", "####.", "#....", "#....", "#####"),
    "I": (".###.", "..#..", "..#..", "..#..", "..#..", ".###."),
    "N": ("#...#", "##..#", "#.#.#", "#.#.#", "#..##", "#...#"),
    "O": (".###.", "#...#", "#...#", "#...#", "#...#", ".###."),
    "U": ("#...#", "#...#", "#...#", "#...#", "#...#", ".###."),
    "Y": ("#...#", "#...#", ".#.#.", "..#..", "..#..", "..#.."),
}

# Letras de calidad carta (LQ), como las de una impresora de 24 agujas: cada
# carácter es una matriz de 36 x 36 posiciones (1/360 de pulgada a lo ancho,
# 1/180 a lo alto) cuyos puntos se solapan. Hay una con remates ("serif") y
# otra de palo seco ("sans"). Las matrices se obtuvieron de las letras libres
# Courier 10 Pitch y DejaVu Sans Mono; sus avisos de derechos están en
# NOTICE.md, en el repositorio. Van comprimidas con zlib y en base64: 162
# bytes por carácter, fila por fila desde arriba; ocho filas quedan por
# debajo del renglón.
LQ_CHARS = [chr(c) for c in range(33, 127)] + [
    chr(c) for c in range(0xC0, 0x100)
    if unicodedata.normalize("NFD", chr(c))[1:] in [a for a, _ in ACCENTS.values()]]
LQ = {
    "serif": (
        "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"),
    "sans": (
        "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"
        "RG8="),
}
_LQ_RAW = {}

# Códigos Epson (ESC + letra) que llevan un parámetro y se ignoran.
ESC_1 = set(b"WSpxk!A3JNQlRtaUsij")
ESC_GRAPHICS = set(b"KLYZ")


# ---------------------------------------------------------------------------
# Intérprete: convierte los bytes que recibió la impresora en páginas
# ---------------------------------------------------------------------------
class Printer:
    """Simula el cabezal: columna, fila, retorno de carro, salto de línea,
    salto de página, tabulador, retroceso y sobreimpresión."""

    def __init__(self):
        self.pages = [{}]        # página: {fila: {columna: [(carácter, negrita)]}}
        self.row = self.col = 0
        self.bold = self.underline = False
        self.pending = {}        # lo impreso desde el último retorno de carro

    def _line_feed(self):
        self.row += 1
        if self.row >= LPP:
            self._new_page()

    def _new_page(self):
        self.pages.append({})
        self.row = 0

    def _settle(self):
        """Pasa a la página lo impreso desde el último retorno de carro.

        Un retorno de carro sin salto de línea vuelve a imprimir sobre la
        misma línea. Eso se respeta cuando es sobreimpresión de verdad, como
        la que usa WordStar: negrita (el mismo carácter otra vez), subrayado
        (guion bajo), tachado (guiones) o acentos. Si en cambio una letra o
        un número taparía a otro distinto, se toma como una línea nueva.
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
        if self.col >= COLS:               # la línea no entra: sigue abajo
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
        """Consume una secuencia ESC de impresora Epson. Aplica negrita y
        subrayado; el resto (tipos de letra, gráficos) se ignora."""
        n = len(d)
        if i >= n:
            return i
        c = d[i]
        i += 1
        if c == 0x40:                      # ESC @  reinicio
            self.bold = self.underline = False
        elif c in b"EG":                   # negrita / doble pasada
            self.bold = True
        elif c in b"FH":
            self.bold = False
        elif c == 0x2D:                    # ESC - n  subrayado
            if i < n:
                self.underline = d[i] in (1, 0x31)
            i += 1
        elif c in ESC_1:
            i += 1
        elif c == 0x43:                    # ESC C n  o  ESC C 0 n
            if i < n and d[i] == 0:
                i += 1
            i += 1
        elif c in b"DB":                   # lista de tabuladores, termina en NUL
            while i < n and d[i] != 0:
                i += 1
            i += 1
        elif c in ESC_GRAPHICS:            # ESC K n1 n2 datos...
            i = i + 2 + d[i] + 256 * d[i + 1] if i + 1 < n else n
        elif c == 0x2A:                    # ESC * m n1 n2 datos...
            i = i + 3 + d[i + 1] + 256 * d[i + 2] if i + 2 < n else n
        return min(i, n)

    def feed(self, data):
        i, n = 0, len(data)
        while i < n:
            b = data[i]
            i += 1
            if b == 0x1B:
                i = self._escape(data, i)
            elif b == 0x0D:                # retorno de carro
                self._settle()
                self.col = 0
            elif b in (0x0A, 0x0B):        # salto de línea
                self._settle()
                self._line_feed()
                self.col = 0
            elif b == 0x0C:                # salto de página
                self._settle()
                if self.row or self.pages[-1]:
                    self._new_page()
                self.col = 0
            elif b == 0x09:                # tabulador cada 8 columnas
                self.col = min((self.col // 8 + 1) * 8, COLS)
            elif b == 0x08:                # retroceso
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


def compose(letter, mark):
    """Letra acentuada que forman una letra y una marca, o None."""
    if mark not in ACCENTS:
        return None
    c = unicodedata.normalize("NFC", letter + ACCENTS[mark][0])
    return c if len(c) == 1 and 0xA0 <= ord(c) <= 0xFF else None


def _dots(ch):
    """Puntos (columna, fila) de un carácter. Filas 0 a 6 sobre el renglón;
    7 y 8 por debajo, como las agujas inferiores de una impresora de 9. Las
    letras acentuadas usan además la fila -1, por encima de la línea."""
    if ord(ch) > 0x7E:                      # letra acentuada: letra + marca
        letter, comb = unicodedata.normalize("NFD", ch)
        rows = next(r for c, r in ACCENTS.values() if c == comb)

        def mark(top):
            return [(i, top + k) for k, row in enumerate(rows)
                    for i, c in enumerate(row) if c == "#"]

        if comb == "\u0327":                # cedilla: debajo del renglón
            return _dots(letter) + mark(7)
        if letter in TALL:                  # mayúscula: seis filas y el acento arriba
            return [(i, 1 + f) for f, row in enumerate(TALL[letter])
                    for i, c in enumerate(row) if c == "#"] + mark(-1)
        # minúscula, sin el punto de la i; la tilde va despegada de la n
        return ([(i, f) for i, f in _dots(letter) if f >= 2]
                + mark(-1 if comb == "\u0303" else 0))
    if ch in DESCENDERS:
        return [(i, f) for f, row in enumerate(DESCENDERS[ch])
                for i, c in enumerate(row) if c == "#"]
    if ch == "_":                          # subraya sin pisar la letra
        return [(i, 8) for i in range(5)]
    base = (ord(ch) - 32) * 5
    return [(i, f) for i, bits in enumerate(GLYPHS[base:base + 5])
            for f in range(7) if bits >> f & 1]


def _lq_rows(font, ch):
    """Filas de un carácter LQ, de arriba hacia abajo: 36 enteros de 36 bits;
    el bit más alto es la columna de la izquierda."""
    if ch not in LQ_CHARS:
        return []
    if font not in _LQ_RAW:
        _LQ_RAW[font] = zlib.decompress(base64.b64decode(LQ[font]))
    i = LQ_CHARS.index(ch) * 162
    n = int.from_bytes(_LQ_RAW[font][i:i + 162], "big")
    return [n >> 36 * (35 - row) & 0xFFFFFFFFF for row in range(36)]


def _glyph_lq(font, ch):
    """Dibujo de un carácter LQ. Los puntos vecinos de una fila se trazan
    juntos, como una línea de extremos redondos del grosor de un punto."""
    s = ["600 0 -30 -300 630 960 d1\n1 J 46 w\n"]
    for row, bits in enumerate(_lq_rows(font, ch)):
        y = _n(916.67 - 33.333 * row)
        col = 0
        while col < 36:
            start = col
            while col < 36 and bits >> (35 - col) & 1:
                col += 1
            if col > start:
                s.append("%s %s m %s %s l\n" % (
                    _n(7.83 + 16.667 * start), y, _n(8.83 + 16.667 * (col - 1)), y))
            col += 1
    return "".join(s) + ("S\n" if len(s) > 1 else "")


def _glyph(font, ch):
    """Dibujo de un carácter: un círculo por cada punto de la matriz.
    Celda de 600 unidades de ancho (milésimas del cuerpo de la letra)."""
    if font != "matrix":
        return _glyph_lq(font, ch)
    dots = _dots(ch)
    s = "600 0 0 -200 600 800 d1\n"
    for col, row in dots:
        s += _circle(100 + 100 * col, 650 - 100 * row, 43)
    return s + ("f\n" if dots else "")


def _background(width, height):
    """Papel continuo: tira perforada a cada lado y franjas verdes."""
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


def _struck(line, col):
    """Indica si una letra vecina también lleva un guion encima: varios
    guiones seguidos son tachado, no una eñe."""
    for near in (col - 1, col + 1):
        chars = [c for c, _ in line.get(near, [])]
        if "-" in chars and any(c.isalnum() for c in chars):
            return True
    return False


def _content(page, x0, height, used, font, paper):
    """Texto de una página. La negrita y la sobreimpresión se logran como
    en una impresora real: una segunda pasada corrida medio punto."""
    s = ["/Bg Do\n"] if paper == "fanfold" else []
    s.append("0.11 0.11 0.17 rg 0.11 0.11 0.17 RG\nBT\n/F1 12 Tf\n")
    # corrimiento de la segunda pasada y distancia del renglón al borde superior
    shift, drop = (0.6, 9.7) if font == "matrix" else (0.4, 8.8)
    for row in sorted(page):
        strikes = []                        # (corrimiento, columna, carácter)
        for col, hits in page[row].items():
            seen = {}
            for ch, bold in hits:
                count, isbold = seen.get(ch, (0, False))
                seen[ch] = (count + 1, isbold or bold)
            letters = [c for c in seen if c.isalpha()]
            if len(letters) == 1:           # una letra con un acento encima
                letter = letters[0]
                for mark in [c for c in seen if c in ACCENTS or c == "-"]:
                    accented = compose(letter, mark)
                    if letter in "nN" and (mark == "^" or (
                            mark == "-" and not _struck(page[row], col))):
                        # eñe escrita con circunflejo o con guion, para teclados
                        # sin tilde, como el de la NABU
                        accented = "\u00f1" if letter == "n" else "\u00d1"
                    if accented:
                        count, isbold = seen.pop(letter)
                        seen.pop(mark)
                        seen[accented] = (count, isbold)
                        break
            for ch, (count, isbold) in seen.items():
                strikes.append((0, col, ch))
                if isbold or count > 1:
                    strikes.append((shift, col, ch))
        layers = []                         # (corrimiento, {columna: carácter})
        for dx, col, ch in strikes:
            used.add(ch)
            for ldx, cells in layers:
                if ldx == dx and col not in cells:
                    cells[col] = ch
                    break
            else:
                layers.append((dx, {col: ch}))
        y = height - 12 * row - drop
        for dx, cells in layers:
            text = "".join(cells.get(c, " ") for c in range(max(cells) + 1))
            s.append("1 0 0 1 %s %s Tm %s Tj\n" % (_n(x0 + dx), _n(y), _string(text)))
    s.append("ET\n")
    return "".join(s)


def _pdf(objects, root, info):
    """Arma el archivo a partir de {número: (diccionario, datos o None)}."""
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
        b"2 beginbfrange\n<20> <7E> <0020>\n<A0> <FF> <00A0>\nendbfrange\n"
        b"endcmap\nCMapName currentdict /CMap defineresource pop\nend\nend\n")


def make_pdf(data, when=None, font=None, paper=None):
    """Devuelve (bytes del PDF, páginas, líneas) o None si no hay nada
    imprimible en los datos. `font` y `paper` son valores de FONTS y PAPERS."""
    font = font if font in FONTS else FONTS[0]
    paper = paper if paper in PAPERS else PAPERS[0]
    pages = Printer().feed(data)
    lines = sum(len(p) for p in pages)
    if not lines:
        return None
    when = when or datetime.datetime.now()
    width, height, x0 = (684, 792, 54) if paper == "fanfold" else (612, 792, 18)

    used = {" "}
    contents = [_content(p, x0, height, used, font, paper) for p in pages]
    chars = sorted(used)

    obj = {}
    CAT, PAGES, FACE, TOUNI, INFO, BG = 1, 2, 3, 4, 5, 6
    nxt = 7 if paper == "fanfold" else 6    # sin papel de fondo no hay objeto BG
    procs = {}
    for ch in chars:
        obj[nxt] = ("<< >>", _glyph(font, ch).encode("latin-1"))
        procs[ch] = nxt
        nxt += 1

    first, last = ord(chars[0]), ord(chars[-1])

    def name(c):
        return NAMES[ord(c) - 32] if ord(c) <= 0x7E else "uni%04X" % ord(c)

    diffs = " ".join("%d /%s" % (ord(c), name(c)) for c in chars)
    obj[FACE] = (
        "<< /Type /Font /Subtype /Type3 /Name /NABU%s "
        "/FontBBox [%s] /FontMatrix [0.001 0 0 0.001 0 0] "
        "/CharProcs << %s >> "
        "/Encoding << /Type /Encoding /Differences [%s] >> "
        "/FirstChar %d /LastChar %d /Widths [%s] "
        "/Resources << /ProcSet [/PDF] >> /ToUnicode %d 0 R >>" % (
            font.capitalize(),
            "0 -200 600 800" if font == "matrix" else "-30 -300 630 960",
            " ".join("/%s %d 0 R" % (name(c), procs[c]) for c in chars),
            diffs, first, last, " ".join(["600"] * (last - first + 1)), TOUNI),
        None)
    obj[TOUNI] = ("<< >>", CMAP)

    resources = "/Font << /F1 %d 0 R >>" % FACE
    if paper == "fanfold":
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
# Servicio
# ---------------------------------------------------------------------------
def lst_path():
    """Ubicación de LST.TXT dentro de la carpeta de almacenamiento del IA."""
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
    """Byte de LST.TXT hasta donde ya se imprimió, o None si no hay registro."""
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


def read_settings():
    """Letra y papel elegidos en el panel web."""
    try:
        with open(SETTINGS) as f:
            s = json.load(f)
    except (OSError, ValueError):
        s = {}
    if not isinstance(s, dict):
        s = {}
    font, paper = s.get("font"), s.get("paper")
    return (font if font in FONTS else FONTS[0],
            paper if paper in PAPERS else PAPERS[0])


def _write(name, data):
    target = os.path.join(DEST, name)
    with open(target + ".part", "wb") as f:
        f.write(data)
    os.replace(target + ".part", target)


def save_pdf(data):
    """Convierte una impresión y la deja en DEST, junto con los datos
    originales (.lst) para poder rehacerla. Devuelve el nombre."""
    now = datetime.datetime.now()
    result = make_pdf(data, now, *read_settings())
    if result is None:
        return None
    pdf, pages, lines = result
    name = "print-%s.pdf" % now.strftime("%Y-%m-%d-%H%M%S")
    _write(name[:-4] + ".lst", data)
    _write(name, pdf)
    print("Impresión guardada: %s (%d página%s, %d línea%s)" % (
        name, pages, "" if pages == 1 else "s",
        lines, "" if lines == 1 else "s"), flush=True)
    return name


def reprint(name):
    """Rehace una impresión guardada con la letra y el papel elegidos ahora.
    Conserva el nombre y, con él, la fecha y la hora originales."""
    m = NAME_RE.fullmatch(name)
    try:
        when = datetime.datetime(*(int(v) for v in m.groups()))
    except (AttributeError, ValueError):
        sys.exit("Nombre de impresión no válido: %s" % name)
    try:
        with open(os.path.join(DEST, name[:-4] + ".lst"), "rb") as f:
            data = f.read()
    except OSError:
        sys.exit("No están los datos originales de %s" % name)
    result = make_pdf(data, when, *read_settings())
    if result is None:
        sys.exit("No hay nada imprimible en los datos de %s" % name)
    _write(name, result[0])
    print("Impresión rehecha: %s" % name, flush=True)


def service():
    os.makedirs(DEST, exist_ok=True)
    lst = lst_path()
    offset = read_state()
    if offset is None:                      # primera vez: no se reimprime lo viejo
        try:
            offset = os.path.getsize(lst)
        except OSError:
            offset = 0
        save_state(offset)
    print("Impresora virtual vigilando %s (leído hasta el byte %d)" % (lst, offset),
          flush=True)
    seen_size, since = offset, time.monotonic()
    while True:
        try:
            size = os.path.getsize(lst)
        except OSError:
            size = 0
        if size < offset:                   # el archivo se vació o se reemplazó
            offset = seen_size = 0
            save_state(0)
        if size != seen_size:               # sigue llegando texto
            seen_size, since = size, time.monotonic()
        elif size > offset and time.monotonic() - since >= WAIT:
            try:
                with open(lst, "rb") as f:
                    f.seek(offset)
                    data = f.read(size - offset)
                save_pdf(data)
            except Exception as e:          # una impresión rota no frena el servicio
                print("No se pudo convertir la impresión: %s" % e,
                      file=sys.stderr, flush=True)
            offset = size
            save_state(offset)
        time.sleep(1)


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--reprint":
        reprint(os.path.basename(sys.argv[2]))
    elif len(sys.argv) == 3:
        with open(sys.argv[1], "rb") as f:
            r = make_pdf(f.read(), None, *read_settings())
        if r is None:
            sys.exit("No hay nada imprimible en %s" % sys.argv[1])
        with open(sys.argv[2], "wb") as f:
            f.write(r[0])
        print("%s: %d página(s), %d línea(s)" % (sys.argv[2], r[1], r[2]))
    elif len(sys.argv) == 1:
        try:
            service()
        except KeyboardInterrupt:
            pass
    else:
        sys.exit("Uso: nabu-print.py [entrada.txt salida.pdf | --reprint print-...pdf]")
PYEOF
sudo chmod 755 /usr/local/lib/nabu/nabu-print.py
mkdir -p "$PRINT_DIR"

if [[ $ASK_PW -eq 1 ]]; then
  echo "==> Guardando contraseña del panel (solo su hash PBKDF2)"
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
  # Conserva la contraseña, pero actualiza el puerto si cambió
  sudo sed -i "s/^PORT=.*/PORT=$PORT/" /etc/nabu-web.conf
fi

echo "==> Instalando panel web"
sudo tee /usr/local/lib/nabu/nabu-web.py >/dev/null <<'PYEOF'
#!/usr/bin/env python3
"""Panel web minimalista para el servidor NABU (solo biblioteca estándar)."""
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
AUTH_OK = set()            # cabeceras ya verificadas (PBKDF2 es lento en una Pi)
UPD = {"state": "idle", "out": ""}
REALM = "Servidor NABU"
UNKNOWN = "desconocido"
NO_POWEROFF = "Sin permiso para apagar la Pi. Vuelve a ejecutar NABU Setup."
NO_PRINT = "Esa impresión ya no existe."
NO_RAW = "No están los datos originales de esa impresión; no se puede rehacer."
BAD_SETTING = "Letra o papel desconocidos."
WHEN = "{d}/{mo}/{y} {h}:{mi}:{s}"     # fecha y hora de cada impresión en la lista
BACKUPS = (os.environ.get("NABU_BACKUP_DIR") or IA.get("NABU_BACKUP_DIR")
           or os.path.expanduser("~/nabu/backups"))
BACKUP_RE = re.compile(r"nabu-backup-[0-9-]+\.zip")
PRINTS = (os.environ.get("NABU_PRINT_DIR") or IA.get("NABU_PRINT_DIR")
          or os.path.expanduser("~/nabu/printer"))
PRINT_RE = re.compile(r"print-(\d{4})-(\d\d)-(\d\d)-(\d\d)(\d\d)(\d\d)\.pdf")
PRINT_MAX = 50             # impresiones que lista el panel (las más nuevas)
PAGES = {}                 # nombre -> (fecha de modificación, páginas)
# Letra y papel de la impresora virtual: las mismas listas que en nabu-print.py,
# que lee la elección de SETTINGS en cada impresión.
FONTS = ("matrix", "serif", "sans")
PAPERS = ("fanfold", "plain")
SETTINGS = os.path.join(PRINTS, ".settings.json")
PRINT_PY = os.path.join(os.path.dirname(os.path.abspath(__file__)), "nabu-print.py")


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


def print_settings():
    """Letra y papel elegidos para la impresora virtual."""
    try:
        with open(SETTINGS) as f:
            s = json.load(f)
    except (OSError, ValueError):
        s = {}
    if not isinstance(s, dict):
        s = {}
    font, paper = s.get("font"), s.get("paper")
    return {"font": font if font in FONTS else FONTS[0],
            "paper": paper if paper in PAPERS else PAPERS[0]}


def prints():
    """Impresiones guardadas por nabu-print, de la más nueva a la más vieja."""
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
                      "pages": cached[1], "kb": max(1, round(st.st_size / 1024)),
                      "raw": os.path.isfile(path[:-4] + ".lst")})
    return dict(print_settings(), items=items, total=len(names))


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
            req = json.loads(self.rfile.read(n) or b"{}")
            action = req.get("action")
        except Exception:
            req, action = {}, None
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
                    {"ok": False, "out": "Ya hay una actualización en curso."}))
            threading.Thread(target=do_update, daemon=True).start()
            self.send(202, json.dumps({"ok": True}))
        elif action == "print-delete":
            name = str(req.get("name", ""))
            path = os.path.join(PRINTS, name)
            if not PRINT_RE.fullmatch(name) or not os.path.isfile(path):
                return self.send(404, json.dumps({"ok": False, "out": NO_PRINT}))
            try:
                os.remove(path)
                if os.path.isfile(path[:-4] + ".lst"):
                    os.remove(path[:-4] + ".lst")
            except OSError as e:
                return self.send(500, json.dumps({"ok": False, "out": str(e)}))
            PAGES.pop(name, None)
            self.send(200, json.dumps({"ok": True}))
        elif action == "print-redo":
            name = str(req.get("name", ""))
            path = os.path.join(PRINTS, name)
            if not PRINT_RE.fullmatch(name) or not os.path.isfile(path):
                return self.send(404, json.dumps({"ok": False, "out": NO_PRINT}))
            if not os.path.isfile(path[:-4] + ".lst"):
                return self.send(404, json.dumps({"ok": False, "out": NO_RAW}))
            rc, out = run(["python3", PRINT_PY, "--reprint", name], 120)
            self.send(200 if rc == 0 else 500, json.dumps({"ok": rc == 0, "out": out}))
        elif action == "print-settings":
            s = {"font": req.get("font"), "paper": req.get("paper")}
            if s["font"] not in FONTS or s["paper"] not in PAPERS:
                return self.send(400, json.dumps({"ok": False, "out": BAD_SETTING}))
            try:
                os.makedirs(PRINTS, exist_ok=True)
                with open(SETTINGS + ".part", "w") as f:
                    json.dump(s, f)
                os.replace(SETTINGS + ".part", SETTINGS)
            except OSError as e:
                return self.send(500, json.dumps({"ok": False, "out": str(e)}))
            self.send(200, json.dumps({"ok": True}))
        elif action == "poweroff":
            rc, _ = run(["sudo", "-n", "-l", "systemctl", "poweroff"])
            if rc != 0:
                return self.send(500, json.dumps({"ok": False, "out": NO_POWEROFF}))
            self.send(200, json.dumps({"ok": True}))
            # se apaga un segundo después, para que el navegador reciba la respuesta
            threading.Timer(1.0, run, [["sudo", "-n", "systemctl", "poweroff"]]).start()
        else:
            self.send(400, json.dumps({"ok": False, "out": "Acción desconocida."}))


PAGE = r"""<!doctype html>
<html lang="es"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="theme-color" content="#001233">
<title>Servidor NABU</title>
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
.btns .wide{grid-column:1/-1}
button.danger{background:transparent;border-color:#7a3340;color:var(--bad)}
.tabs{display:flex;gap:8px;margin-bottom:10px}
.tabs button{flex:1;padding:8px}
.tabs button.on{border-color:var(--acc);color:var(--acc)}
pre{margin:0;background:#000a1f;border-radius:8px;padding:10px;overflow:auto;
font:12px/1.35 ui-monospace,"DejaVu Sans Mono",monospace;max-height:55vh;white-space:pre}
#msg{min-height:1.4em;color:var(--dim);font-size:.9rem;margin-top:10px}
.plist{list-style:none;margin:0;padding:0;max-height:40vh;overflow:auto}
.plist li{display:flex;align-items:baseline;gap:12px;
padding:3px 0;border-top:1px solid var(--line)}
.plist li:first-child{border-top:0}
.plist a{flex:1;color:var(--acc);text-decoration:none;font-weight:600;font-variant-numeric:tabular-nums}
.plist small{color:var(--dim);font-size:.82rem;white-space:nowrap}
.plist .empty{color:var(--dim);font-size:.9rem;padding:10px 0}
.plist button.del{background:transparent;border:0;color:var(--bad);font-size:1.05rem;
line-height:1;padding:9px 11px;margin-right:-11px;border-radius:8px}
.plist button.del:hover{background:rgba(255,107,107,.14)}
.plist button.redo{background:transparent;border:0;color:var(--acc);font-size:1.05rem;
line-height:1;padding:9px 9px;margin-right:-10px;border-radius:8px}
.plist button.redo:hover{background:rgba(78,168,255,.14)}
.opt{display:flex;flex-wrap:wrap;align-items:center;gap:0 16px;margin:0 0 2px}
.opt>span{flex:0 0 100%;color:var(--dim);font-size:.82rem}
.opt label{display:flex;align-items:center;gap:7px;padding:6px 0;cursor:pointer;white-space:nowrap}
.opt input{accent-color:var(--acc);width:1.05em;height:1.05em;margin:0}
.hint{color:var(--dim);font-size:.82rem;margin:4px 0 10px;min-height:1.3em}
.hint.bad{color:var(--bad)}
footer{color:var(--dim);font-size:.78rem;text-align:center;padding:2px 0 14px}
footer a{color:inherit}
</style></head><body><main>
<h1>Servidor <span>NABU</span></h1>

<div class="card"><div class="grid">
<div class="item" id="s-svc"><small>Internet Adapter</small><b><span class="dot"></span><span>…</span></b></div>
<div class="item" id="s-tty"><small>Adaptador RS422</small><b><span class="dot"></span><span>…</span></b></div>
<div class="item" id="s-temp"><small>Temperatura</small><b><span class="dot"></span><span>…</span></b></div>
<div class="item" id="s-pwr"><small>Alimentación</small><b><span class="dot"></span><span>…</span></b></div>
</div></div>

<div class="card">
<div class="btns">
<button class="main" onclick="act('restart',T.restarting)">Reiniciar</button>
<button id="b-toggle" onclick="toggle()">Detener</button>
<button onclick="backup()" id="b-bak">Backup</button>
<button onclick="update()" id="b-upd">Actualizar IA</button>
<button class="wide danger" onclick="poweroff()">Apagar la Pi</button>
</div>
<div id="msg"></div>
</div>

<div class="card">
<h2>Impresiones</h2>
<div class="opt" role="radiogroup" aria-labelledby="o-font"><span id="o-font">Tipo de letra</span>
<label><input type="radio" name="font" value="matrix" onchange="setOpt()">Matriz de puntos</label>
<label><input type="radio" name="font" value="serif" onchange="setOpt()">Serif</label>
<label><input type="radio" name="font" value="sans" onchange="setOpt()">Sans serif</label>
</div>
<div class="opt" role="radiogroup" aria-labelledby="o-paper"><span id="o-paper">Tipo de papel</span>
<label><input type="radio" name="paper" value="plain" onchange="setOpt()">Blanco</label>
<label><input type="radio" name="paper" value="fanfold" onchange="setOpt()">Formulario continuo</label>
</div>
<div class="hint" id="p-hint"></div>
<ul class="plist" id="prints"><li class="empty">…</li></ul>
</div>

<div class="card">
<div class="tabs">
<button id="t-screen" class="on" onclick="tab('screen')">Pantalla</button>
<button id="t-log" onclick="tab('log')">Registro</button>
<button onclick="loadView()" title="Actualizar">↻</button>
</div>
<pre id="view">…</pre>
</div>
<footer>@@FOOTER@@</footer>
</main>
<script>
const T={
  active:'Activo', inactive:'Detenido', failed:'Con error', activating:'Arrancando',
  deactivating:'Deteniéndose',
  notDetected:'No detectado', powerOk:'OK', powerBad:'Problemas',
  stop:'Detener', start:'Iniciar',
  restarting:'Reiniciando…', stopping:'Deteniendo…', starting:'Iniciando…',
  confirmStop:'¿Detener el Internet Adapter?',
  done:'Listo.', error:'Error: ', noConn:'Error de conexión.', noPi:'Sin conexión con la Pi.',
  updating:'Actualizando… puede tardar unos minutos.',
  confirmUpdate:'¿Descargar e instalar la última versión del Internet Adapter? Se hace un backup antes.',
  updateOk:'Actualización completa.', updateFail:'La actualización falló (ver Registro).',
  backingUp:'Creando backup…', backupOk:'Backup creado: ', downloading:'. Descargando…',
  backupFail:'Error al crear el backup: ',
  confirmOff:'¿Apagar la Pi? Para volver a encenderla tendrás que cortar y devolver la corriente.',
  poweringOff:'Apagando la Pi… Espera a que el LED verde deje de parpadear antes de cortar la corriente.',
  empty:'(vacío)', loadFail:'No se pudo cargar.',
  printerOff:'La impresora virtual no está activa.',
  noPrints:'Todavía no hay impresiones. Prueba LPRINT desde MBASIC.',
  page:' página', pages:' páginas',
  del:'Borrar', confirmDel:w=>'¿Borrar la impresión del '+w+'?',
  redo:'Rehacer con la letra y el papel elegidos', redoing:'Rehaciendo la impresión…',
  hint:'Vale para las próximas impresiones. Con ↻ se rehace una ya impresa.',
  older:n=>'Hay '+n+' más antiguas en la carpeta de impresiones.'
};
let view='screen', active='', printer=true, printsKey='', off=false;
const $=id=>document.getElementById(id);
async function api(p,opt){const r=await fetch(p,opt);return r.json();}
function set(id,cls,txt){const e=$(id);e.className='item '+cls;e.querySelector('b span:last-child').textContent=txt;}
function msg(t){$('msg').textContent=t||'';}
function post(a,extra){return api('/api/action',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(Object.assign({action:a},extra||{}))});}
async function refresh(){
  if(off) return;
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
async function poweroff(){
  if(!confirm(T.confirmOff))return;
  try{const r=await post('poweroff'); if(r.ok){off=true; msg(T.poweringOff);} else msg(T.error+r.out);}
  catch(e){msg(T.noConn);}
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
  for(const k of ['font','paper']){const e=document.querySelector('input[name='+k+'][value="'+r[k]+'"]'); if(e) e.checked=true;}
  const ul=$('prints'); ul.textContent='';
  const note=t=>{const li=document.createElement('li');li.className='empty';li.textContent=t;ul.appendChild(li);};
  if(!printer) note(T.printerOff);
  if(!r.items.length && printer) note(T.noPrints);
  for(const p of r.items){
    const li=document.createElement('li'), a=document.createElement('a'), s=document.createElement('small'), x=document.createElement('button');
    a.href='/api/print/'+encodeURIComponent(p.name); a.target='_blank'; a.rel='noopener'; a.textContent=p.when;
    s.textContent=p.pages+(p.pages===1?T.page:T.pages)+' · '+p.kb+' KB';
    x.className='del'; x.textContent='✕'; x.title=T.del; x.setAttribute('aria-label',T.del+' '+p.when);
    x.onclick=()=>delPrint(p);
    li.appendChild(a); li.appendChild(s);
    if(p.raw){
      const b=document.createElement('button');
      b.className='redo'; b.textContent='↻'; b.title=T.redo; b.setAttribute('aria-label',T.redo+': '+p.when);
      b.onclick=()=>redoPrint(p,b);
      li.appendChild(b);
    }
    li.appendChild(x); ul.appendChild(li);
  }
  if(r.total>r.items.length) note(T.older(r.total-r.items.length));
}
function pnote(t,bad){const e=$('p-hint'); e.textContent=t||T.hint; e.classList.toggle('bad',!!bad);}
async function delPrint(p){
  if(!confirm(T.confirmDel(p.when)))return;
  try{const r=await post('print-delete',{name:p.name}); pnote(r.ok?'':T.error+r.out,!r.ok);}
  catch(e){pnote(T.noConn,true);}
  printsKey=''; loadPrints();
}
async function redoPrint(p,b){
  b.disabled=true; pnote(T.redoing);
  try{const r=await post('print-redo',{name:p.name}); pnote(r.ok?'':T.error+r.out,!r.ok);}
  catch(e){pnote(T.noConn,true);}
  printsKey=''; loadPrints();
}
async function setOpt(){
  const f=document.querySelector('input[name=font]:checked'), p=document.querySelector('input[name=paper]:checked');
  if(!f||!p) return;
  try{const r=await post('print-settings',{font:f.value,paper:p.value}); pnote(r.ok?'':T.error+r.out,!r.ok);}
  catch(e){pnote(T.noConn,true);}
  printsKey=''; loadPrints();
}
pnote(); refresh(); loadView();
setInterval(refresh,10000);
setInterval(()=>{ if(view==='screen'&&!off) loadView(); },5000);
</script></body></html>"""


def footer():
    """Pie del panel: versión y fecha de NABU Setup, con enlace al repositorio."""
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
    print(f"Panel NABU escuchando en el puerto {PORT}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
PYEOF
sudo chmod 755 /usr/local/lib/nabu/nabu-web.py

echo "==> Creando servicio systemd nabu-web"
sudo tee /etc/systemd/system/nabu-web.service >/dev/null <<EOF
[Unit]
Description=Panel web del servidor NABU
After=network-online.target
Wants=network-online.target

[Service]
User=$U
# Único permiso extra: abrir puertos menores a 1024 (el panel usa el 80).
# Sin CapabilityBoundingSet: el panel necesita sudo para controlar nabu-ia.
AmbientCapabilities=CAP_NET_BIND_SERVICE
ExecStart=/usr/bin/python3 /usr/local/lib/nabu/nabu-web.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

echo "==> Creando servicio systemd nabu-print"
sudo tee /etc/systemd/system/nabu-print.service >/dev/null <<EOF
[Unit]
Description=Impresora virtual del servidor NABU (LST.TXT a PDF)

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
  echo "Instalación completa. Reinicia la Pi para aplicar los permisos nuevos:"
  echo "    sudo reboot"
  echo
  echo "Después:"
  echo "  - Por SSH:    nabu         (la primera vez, elige /dev/ttyUSB0 en Settings)"
else
  echo "NABU Setup $NABU_SETUP_VERSION aplicado. No hace falta reiniciar la Pi ni el Internet Adapter."
  echo
  echo "  - Por SSH:    nabu"
fi
echo "  - Panel web:  http://$(hostname).local   o   http://$IP"
echo "                usuario: nabu"
echo "  - Impresora:  lo que imprimas desde Cloud CP/M (LST:) aparece como PDF"
echo "                en el panel y en $PRINT_DIR"
echo "  - Ayuda:      nabu help"
echo "  - Manual:     $NABU_SETUP_REPO"
