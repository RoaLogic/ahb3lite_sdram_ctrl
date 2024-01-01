---
title: Test & Debug
permalink: /test/
---
# {{page.title}}

(**Include Test**)

{% include roalogic/about.md %}

## Contact

(**Parameter Test**)

{% include roalogic/contact.md emailsubject=site.url %}

## Meta-Test

(**GH Metadata Test**)

{% include debug/meta_test.md %}

{{ site.github.source.branch }}

---

## Markdown

(**Markdown Styling Demo**)

{% include debug/markdown.md %}
