- Files:
  - [_config.yml][]: Site Configuration
  - [Gemfile][]:     Offline Deployment Configuration

- Folders
  - [_data][]:     Site data, stored in YAML format
  - [_includes][]: Resusable smippets of text and code
  - [_layouts][]:  Page layouts
  - [_pages][]:    Site content
  - [_sass][]:     Site styling
  - [assets][]:    Site graphics & scripts

{% capture dirpath %}{{ site.github.repository_url | append: "/tree/" | append: site.github.source.branch }}{% endcapture %}

{% capture filepath %}{{ site.github.repository_url | append: "/blob/" | append: site.github.source.branch }}{% endcapture %}

[_data]:     {{ dirpath | append: "/_data" }}
[_includes]: {{ dirpath | append: "/_includes" }}
[_layouts]:  {{ dirpath | append: "/_layouts" }}
[_pages]:    {{ dirpath | append: "/_pages" }}
[_sass]:     {{ dirpath | append: "/_sass" }}
[assets]:    {{ dirpath | append: "/assets" }}

[_config.yml]: {{ filepath | append: "/_config.yml" }}
[Gemfile]:     {{ filepath | append: "/Gemfile" }}
