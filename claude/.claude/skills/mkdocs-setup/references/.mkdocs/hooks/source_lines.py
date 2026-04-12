"""Inject data-source-line attributes into rendered HTML block elements.

Heuristic approach: save the original Markdown in on_page_markdown,
then in on_page_content match HTML block elements back to source lines
using a forward-scanning algorithm.  Elements that cannot be matched
with sufficient confidence are silently skipped.
"""

import re
from bs4 import BeautifulSoup, NavigableString

# Per-page storage: page.file.src_path -> markdown text
_md_store: dict[str, str] = {}


def on_page_markdown(markdown, page, **kwargs):
    """Save the original Markdown text for later matching."""
    _md_store[page.file.src_path] = markdown
    return markdown


def on_page_content(html, page, **kwargs):
    """Annotate block-level HTML elements with data-source-line."""
    md_text = _md_store.pop(page.file.src_path, None)
    if not md_text:
        return html

    lines = md_text.split("\n")
    soup = BeautifulSoup(html, "html.parser")

    cursor = 0  # current scan position in Markdown lines

    # Process only direct children of the root that are block elements
    for element in soup.children:
        if isinstance(element, NavigableString):
            continue

        matched_line = _match_element(element, lines, cursor)
        if matched_line is not None:
            element["data-source-line"] = str(matched_line + 1)  # 1-indexed
            cursor = matched_line + 1

    return str(soup)


def _match_element(element, lines, cursor):
    """Try to find the source line for an HTML element.

    Returns the 0-indexed line number, or None if no confident match.
    """
    tag = element.name

    if tag in ("h1", "h2", "h3", "h4", "h5", "h6"):
        return _match_heading(element, lines, cursor)
    elif tag == "p":
        return _match_paragraph(element, lines, cursor)
    elif tag == "pre":
        return _match_code_block(lines, cursor)
    elif tag == "table":
        return _match_table(lines, cursor)
    elif tag in ("ul", "ol"):
        return _match_list(element, lines, cursor)
    elif tag == "blockquote":
        return _match_blockquote(lines, cursor)
    elif tag == "div":
        return _match_div(element, lines, cursor)
    elif tag == "hr":
        return _match_hr(lines, cursor)

    return None


def _match_heading(element, lines, cursor):
    """Match <h1>-<h6> to # lines."""
    level = int(element.name[1])
    prefix = "#" * level + " "
    text = _get_text(element).strip()

    for i in range(cursor, len(lines)):
        line = lines[i].strip()
        if line.startswith(prefix):
            heading_text = line[len(prefix):].strip()
            # Remove trailing # (e.g. "## Foo ##")
            heading_text = heading_text.rstrip("#").strip()
            if _text_similar(heading_text, text):
                return i
    return None


def _match_paragraph(element, lines, cursor):
    """Match <p> to the first line of a paragraph block."""
    text = _get_text(element).strip()
    if not text:
        return None

    # Take the first ~40 chars for matching
    snippet = text[:40]

    for i in range(cursor, len(lines)):
        line = lines[i].strip()
        if not line:
            continue
        # Skip lines that are clearly not paragraphs
        if _is_structural_line(line):
            continue
        # Check if the Markdown line content appears in the paragraph text
        # or vice versa (inline markup gets stripped in HTML text)
        clean_line = _strip_inline_markup(line)
        if _text_similar(clean_line[:40], snippet[:40]):
            return i
    return None


def _match_code_block(lines, cursor):
    """Match <pre> to fenced code block (``` or ~~~)."""
    for i in range(cursor, len(lines)):
        line = lines[i].strip()
        if re.match(r"^(`{3,}|~{3,})", line):
            return i
    return None


def _match_table(lines, cursor):
    """Match <table> to the first | line."""
    for i in range(cursor, len(lines)):
        line = lines[i].strip()
        if line.startswith("|"):
            return i
    return None


def _match_list(element, lines, cursor):
    """Match <ul>/<ol> to the first list item line."""
    is_ordered = element.name == "ol"

    for i in range(cursor, len(lines)):
        line = lines[i].strip()
        if is_ordered and re.match(r"^\d+\.\s", line):
            return i
        elif not is_ordered and re.match(r"^[-*+]\s", line):
            return i
    return None


def _match_blockquote(lines, cursor):
    """Match <blockquote> to > lines."""
    for i in range(cursor, len(lines)):
        line = lines[i].strip()
        if line.startswith(">"):
            return i
    return None


def _match_div(element, lines, cursor):
    """Match <div> — typically admonitions (!!!/???) or other pymdownx output."""
    classes = element.get("class", [])

    # Admonition: <div class="admonition ..."> or <div class="details ...">
    is_admonition = any(
        c in classes for c in ("admonition", "details", "note", "tip",
                               "warning", "danger", "info", "example",
                               "question", "abstract", "success", "failure",
                               "bug", "quote")
    )
    if is_admonition:
        for i in range(cursor, len(lines)):
            line = lines[i].strip()
            if re.match(r"^(!{3}|[?]{3})\s", line):
                return i
        return None

    # Tabbed content: <div class="tabbed-set ...">
    if "tabbed-set" in classes:
        for i in range(cursor, len(lines)):
            line = lines[i].strip()
            if line.startswith("==="):
                return i
        return None

    return None


def _match_hr(lines, cursor):
    """Match <hr> to --- / *** / ___ lines."""
    for i in range(cursor, len(lines)):
        line = lines[i].strip()
        if re.match(r"^([-*_])\1{2,}$", line):
            return i
    return None


# --- Helpers ---

def _get_text(element):
    """Get concatenated text content of an element."""
    return element.get_text()


def _strip_inline_markup(text):
    """Remove common Markdown inline markup for comparison."""
    text = re.sub(r"\*{1,2}(.+?)\*{1,2}", r"\1", text)
    text = re.sub(r"_{1,2}(.+?)_{1,2}", r"\1", text)
    text = re.sub(r"`(.+?)`", r"\1", text)
    text = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", text)
    text = re.sub(r"~~(.+?)~~", r"\1", text)
    return text


def _text_similar(a, b):
    """Check if two text snippets are similar enough."""
    if not a or not b:
        return False
    a = re.sub(r"\s+", " ", a).strip().lower()
    b = re.sub(r"\s+", " ", b).strip().lower()
    # One contains the other, or they share a significant prefix
    if a.startswith(b[:20]) or b.startswith(a[:20]):
        return True
    if a in b or b in a:
        return True
    return False


def _is_structural_line(line):
    """Check if a line is clearly a non-paragraph structural element."""
    if line.startswith("#"):
        return True
    if re.match(r"^(`{3,}|~{3,})", line):
        return True
    if line.startswith("|"):
        return True
    if re.match(r"^[-*+]\s", line):
        return True
    if re.match(r"^\d+\.\s", line):
        return True
    if line.startswith(">"):
        return True
    if re.match(r"^(!{3}|[?]{3})\s", line):
        return True
    if re.match(r"^([-*_])\1{2,}$", line):
        return True
    if line.startswith("==="):
        return True
    return False
