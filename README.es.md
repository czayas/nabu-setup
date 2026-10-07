# NABU Setup

[English](README.md) · **Español**

NABU Setup es un script de instalación que convierte una Raspberry Pi en un pequeño servidor para la [computadora NABU](https://en.wikipedia.org/wiki/NABU_Network). Descarga el [NABU Internet Adapter](https://nabu.ca/downloads-nabu-internet-adapter) oficial, lo deja funcionando como servicio y agrega las herramientas para administrarlo desde una terminal o desde un teléfono.

Versión actual: **1.4.0**, publicada el 2026-10-06. Consulta el [registro de cambios](CHANGELOG.es.md).

![Componentes de un servidor NABU instalado con NABU Setup](docs/img/architecture-es.png)

## Qué instala

- **El NABU Internet Adapter como servicio.** Arranca cuando se enciende la Pi, sin esperar a la red, y se reinicia si se cierra. Corre dentro de una sesión de `tmux`, así que puedes abrir su interfaz de texto por SSH y dejarlo en marcha.
- **El comando `nabu`**, para consultar, iniciar, detener y actualizar el servidor, hacer backups y apagar la Pi de forma segura.
- **Un panel web** en el puerto 80, protegido con contraseña, con indicadores de estado, botones de control (incluido el apagado seguro), una vista en vivo de la pantalla del Internet Adapter, el registro del servicio y las novedades de nabu.ca. Avisa cuando hay una versión nueva del Internet Adapter.
- **Una impresora virtual.** Lo que la NABU imprime en el dispositivo `LST:` desde Cloud CP/M se convierte en un PDF. Se puede elegir entre una letra de matriz de puntos y dos de calidad carta, y entre papel continuo y papel blanco. Admite negrita, subrayado, la sobreimpresión que usa WordStar y letras acentuadas.
- **Backups** de las unidades de CP/M, los programas locales y la configuración, en archivos .zip. Se conservan los últimos cinco.

Todo lo que no es el Internet Adapter está hecho en Bash y Python, sin más bibliotecas que las estándar.

## Requisitos

- Una Raspberry Pi con procesador ARMv7 o ARMv8: Pi 2, 3, 4, 5 o Zero 2 W. La Pi 1, la Zero y la Zero W no pueden ejecutar el Internet Adapter.
- Raspberry Pi OS Lite, preferentemente de 64 bits, con SSH activado.
- Un adaptador USB a RS-422 y un cable hasta la NABU. Consulta [Make NABU Cable](https://nabu.ca/Make-NABU-Cable).

Se desarrolló y se probó en una Raspberry Pi 3 Model A+.

## Instalación

En la Pi, con tu usuario normal:

```
wget https://raw.githubusercontent.com/czayas/nabu-setup/main/nabu-setup-es.sh
bash nabu-setup-es.sh
sudo reboot
```

El script pide una contraseña para el panel web y hace el resto por su cuenta. Se puede volver a ejecutar sin problemas, por ejemplo para cambiar esa contraseña. Para instalar más adelante una versión nueva, ejecuta `nabu setup`.

Hay dos ediciones con el mismo código y distinto idioma: `nabu-setup-es.sh` (español) y `nabu-setup-en.sh` (inglés).

## El comando `nabu`

| Comando | Qué hace |
|---|---|
| `nabu` | Entra a la interfaz del Internet Adapter. Se sale con Ctrl-b y después d |
| `nabu status` | Servicio, adaptador RS-422, impresora virtual, temperatura y alimentación |
| `nabu list` | Registro del servicio y errores del Internet Adapter |
| `nabu start`, `stop`, `restart` | Controlan el Internet Adapter |
| `nabu backup` | Guarda un backup en `~/nabu/backups` |
| `nabu update` | Actualiza el Internet Adapter, después de hacer un backup |
| `nabu setup` | Actualiza el propio NABU Setup a la última versión publicada |
| `nabu poweroff` | Apaga la Pi de forma segura antes de cortar la corriente |
| `nabu version` | Muestra la versión y la fecha de NABU Setup |
| `nabu help` | Muestra la ayuda |

El panel web está en `http://nabu.local` (usuario `nabu`). Las impresiones se guardan en `~/nabu/printer`.

## Documentación

El manual de usuario presenta la NABU y su historia, explica cómo preparar la Pi y trae un tutorial de cada función.

| | PDF | Fuente |
|---|---|---|
| Español | [nabu-setup-manual-es.pdf](docs/nabu-setup-manual-es.pdf) | [docs/es/manual.md](docs/es/manual.md) |
| Inglés | [nabu-setup-manual-en.pdf](docs/nabu-setup-manual-en.pdf) | [docs/en/manual.md](docs/en/manual.md) |

Las fuentes están en Markdown para Pandoc. Para regenerar los PDF hacen falta `pandoc`, XeLaTeX (TeX Live, con soporte para español) y la fuente DejaVu Sans Mono:

```
cd docs
make
```

## Licencia

NABU Setup y su documentación se publican bajo la [licencia BSD de 2 cláusulas](LICENSE). La licencia cubre solamente NABU Setup, no el NABU Internet Adapter, que el script descarga del sitio de su autor.

## Créditos

El NABU Internet Adapter, Cloud CP/M y RetroNET son obra de DJ Sures ([nabu.ca](https://nabu.ca)). NABU Setup es un proyecto independiente y no está afiliado a nabu.ca.

Las letras de calidad carta de la impresora virtual se obtuvieron de Courier 10 Pitch y DejaVu Sans Mono. Sus avisos de derechos están en [NOTICE.md](NOTICE.md).

NABU Setup es un proyecto de Retro Informática Paraguay: <https://www.youtube.com/@retroinfopy>
