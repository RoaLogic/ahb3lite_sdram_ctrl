# ReadMe: AHB-Lite SDRAM Controller

## Overview

Description goes here

## Documentation

The **`/docs`** subfolder is a self contained sub-repository of all documentation for the `ahb3lite_sdram_controller` IP

All documentation is written in LaTeX from which a standalone PDF datasheet and HTML data sheet (via markdown) are generated. The HTML datasheet is served via GitHub pages

The following sections describe in detail the contents of this sub-repository

### LaTeX Source:

All documentation generated from LaTex Source

- Top Level: [{{ "_datasheet.tex" | prepend: site.project }}]( {{ "_datasheet.tex" | prepend: site.project | prepend: "./" }} )
- Directories:
  - `tex/` → Datasheet Content
  - `pkg/` → Layout definition
  - `assets/` → Graphics Content, including source files

### PDF: 

Compiled from LaTeX source using pdfLaTeX

- Generated as → [{{ "_datasheet.pdf" | prepend: site.project }}]( {{ "_datasheet.pdf" | prepend: site.project | prepend: "./" }} )

### Markdown: 

Generated from LaTeX source via 'pandoc' utility

- Generated as → [{{ "_datasheet.md" | prepend: site.project }}]( {{ "_datasheet.md" | prepend: site.project | prepend: "./" }} )
  - `markdown/` → Compilation script(s) to create markdown
  - `readme.md` → This file

### HTML:

Generated via GitHub Pages (ie jekyll static generator)

- Generated as → [https://roalogic.github.io/ahb3lite_interconnect]( {{site.url}}{{site.baseurl}})
- Directories:
  - `_pages/` → Non-datasheet content
  - `_layout/` → Custom page generation layout
  - `_sass/` → Style sheets (.sccs format)
  - `_data/` → Site / project specific data
- `_config.yml` → jekyll configuration
- `Gemfile` → offline environment setup (ignored by GH pages)
- `favicon.ico` → Site icon # ReadMe: GH Pages & Doc's Templates

## Contact

![Roa Logic Logo][]  
**Roa Logic BV**  
Burgemeester Snijdersstraat 17  
6363BG Wijnandsrade  
The Netherlands

☎︎ [+31 (45) 405 5681][Roa Logic Phone]  
✉︎ [info@roalogic.com][Roa Logic Email]  
➤ [https://roalogic.com][Roa Logic Website]

IBAN: NL75 INGB 0006 5617 87, BIC: INGBNL2A

KvK Zuid-Limburg: 61368962  
BTW: NL854314283B01

[Roa Logic Logo]:              /assets/img/RoaLogicHeader.png  
[Roa Logic Email]:             mailto:info@roalogic.com  
[Roa Logic Website]:           https://roalogic.com  
[Roa Logic Phone]:             tel:+31454055681  
[Roa Logic Repos]:             https://github.com/roalogic 
