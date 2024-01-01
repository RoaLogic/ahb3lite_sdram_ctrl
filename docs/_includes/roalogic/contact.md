
{% comment %}Determine Email Subject, if specified{% endcomment %}
{% if include.emailsubject %}
  {% assign esubject = "?subject=" | append: include.emailsubject %}
{% endif %}

![Roa Logic Logo]({{site.data.images.rlheader|relative_url}})  
**Roa Logic BV**  
Burgemeester Snijdersstraat 17  
6363BG Wijnandsrade  
The Netherlands

☎︎ [+31 (45) 405 5681][contact_phone]  
✉︎ [info@roalogic.com][contact_email]  
➤ [https://roalogic.com][contact_website]

IBAN: NL75 INGB 0006 5617 87, BIC: INGBNL2A

KvK Zuid-Limburg: 61368962  
BTW: NL854314283B01

[contact_phone]:   {{site.data.links.phone}}  
[contact_email]:   mailto:{{site.data.links.email|append:esubject}}
[contact_website]: {{site.data.links.website}}
