# Registro de cambios

[English](CHANGELOG.md)

NABU Setup y su manual llevan numeraciones separadas. El script usa números de versión (como 1.2.0); el manual usa números de revisión e indica a qué versión del script corresponde.

## NABU Setup 1.3.0 (2026-10-05)

- La impresora virtual forma letras acentuadas: un acento impreso sobre una letra, como hace WordStar con `^PH`, se dibuja como una sola letra (á, é, ñ, ü, ç y las demás de Latin-1) y queda así en el texto del PDF.
- La eñe también se puede escribir con un guion o con `^` sobre la `n`, porque el teclado de la NABU no tiene la tecla `~`.
- La impresora virtual tiene dos letras nuevas de calidad carta, *Serif* y *Sans serif*, además de la de matriz de puntos, y puede imprimir en papel blanco además del formulario continuo. Se eligen en el panel web.
- Cada impresión guarda sus datos originales, y un botón nuevo del panel la rehace con la letra y el papel elegidos, sin volver a imprimir desde la NABU.
- Nuevo botón en el panel web para borrar cada impresión.
- Los backups se guardan ahora en `~/nabu/backups`. Al instalar esta versión, los que haya en `~/backups` se mudan solos a la carpeta nueva.
- La impresión desde WordStar quedó verificada en una NABU real.
- Corrección: la opción `PAPER = False` de las versiones anteriores no generaba el PDF. La reemplaza la elección de papel del panel.

## NABU Setup 1.2.0 (2026-10-04)

- Nuevo comando `nabu setup`: descarga la última versión publicada de NABU Setup, la compara con la instalada y la instala.

## NABU Setup 1.1.0 (2026-10-04)

- Nuevo comando `nabu poweroff`: apaga la Pi de forma segura antes de cortar la corriente.
- Nuevo botón **Apagar la Pi** en el panel web.
- El instalador ahora también permite que el panel apague la Pi sin contraseña.

## NABU Setup 1.0.0 (2026-10-03)

Primera versión publicada.

- Instala el NABU Internet Adapter como servicio de systemd dentro de una sesión de `tmux`.
- Comando de administración `nabu`: `status`, `list`, `start`, `stop`, `restart`, `backup`, `update`, `version` y `help`.
- Panel web en el puerto 80, protegido con contraseña.
- Impresora virtual: lo que la NABU envía a `LST:` se convierte en un PDF en `~/nabu/printer`.
- Backups en archivos .zip en `~/backups`; se conservan los últimos cinco.
- Dos ediciones con el mismo código: `nabu-setup-es.sh` (español) y `nabu-setup-en.sh` (inglés).

## Manual

| Revisión | Fecha | NABU Setup | Cambios |
|---|---|---|---|
| 4 | 2026-10-05 | 1.3.0 | Acentos y eñe, impresión desde WordStar, letra y papel, borrado y reimpresión, carpeta de backups |
| 3 | 2026-10-04 | 1.2.0 | Comando `nabu setup` |
| 2 | 2026-10-04 | 1.1.0 | Apagado seguro: `nabu poweroff` y el botón del panel |
| 1 | 2026-10-03 | 1.0.0 | Primera publicación |
