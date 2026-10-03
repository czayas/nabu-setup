# Genera los PDF del manual a partir de las fuentes en Markdown.
# Builds the manual PDFs from the Markdown sources.
#
#   make        los dos idiomas / both languages
#   make es     solo español / Spanish only
#   make en     solo inglés / English only
#
# Requisitos / Requirements: pandoc, XeLaTeX (TeX Live), DejaVu Sans Mono.

PANDOC = pandoc --from=markdown --pdf-engine=xelatex --template=../template.tex \
         --lua-filter=../figures.lua

all: es en

es: nabu-setup-manual-es.pdf
en: nabu-setup-manual-en.pdf

nabu-setup-manual-%.pdf: %/manual.md template.tex figures.lua
	cd $* && $(PANDOC) manual.md -o ../$@

clean:
	rm -f nabu-setup-manual-es.pdf nabu-setup-manual-en.pdf

.PHONY: all es en clean
