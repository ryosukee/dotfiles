"""Inject YAML front matter as a collapsible admonition at the top of each page."""

import re


def on_page_markdown(markdown, page, **kwargs):
    path = page.file.abs_src_path
    with open(path, encoding="utf-8") as f:
        raw = f.read()

    m = re.match(r"^---\n(.+?\n)---\n", raw, re.DOTALL)
    if not m:
        return markdown

    front_matter = m.group(1).rstrip("\n")
    indented = "\n".join(f"    {line}" for line in front_matter.split("\n"))
    block = f'???+ info "Front Matter"\n\n    ```yaml\n{indented}\n    ```\n\n'
    return block + markdown
