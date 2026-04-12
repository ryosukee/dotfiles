"""Convert .yaml files under docs/ into .md files on the fly for mkdocs.

Before mkdocs reads files, this hook finds all .yaml files in docs_dir
and creates a corresponding .md file (sibling) that wraps the YAML content
in a code block. The generated .md files are cleaned up after build.
"""

import os

_generated = []


def on_pre_build(config, **kwargs):
    """Generate .md wrappers for all .yaml files in docs_dir."""
    docs_dir = config["docs_dir"]
    for root, dirs, filenames in os.walk(docs_dir, followlinks=True):
        for filename in filenames:
            if not filename.endswith(".yaml"):
                continue
            yaml_path = os.path.join(root, filename)
            md_path = yaml_path.replace(".yaml", ".md")
            if os.path.exists(md_path):
                continue
            name = os.path.splitext(filename)[0]
            with open(yaml_path, encoding="utf-8") as f:
                content = f.read()
            with open(md_path, "w", encoding="utf-8") as f:
                f.write(f"# {name}\n\n```yaml\n{content}```\n")
            _generated.append(md_path)


def on_post_build(config, **kwargs):
    """Clean up generated .md files."""
    for path in _generated:
        if os.path.exists(path):
            os.remove(path)
    _generated.clear()
