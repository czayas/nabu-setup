# Registro de cambios

[English](CHANGELOG.md)

NABU Setup y su manual llevan numeraciones separadas. El script usa números de versión (1.0.0); el manual usa números de revisión e indica a qué versión del script corresponde.

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
| 1 | 2026-10-03 | 1.0.0 | Primera publicación |
