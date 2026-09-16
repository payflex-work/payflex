#!/usr/bin/env python3
"""Check relative links (and same-page anchors) in the repo's markdown docs.

Scope: the root README.md and everything under docs/ — the surfaces a PR
touches when it edits documentation. External http(s) links are out of
scope: a URL can be down for reasons a doc PR neither caused nor can fix.

Checks:
  1. Relative links to files resolve (../ and ./ handled, URL-decoded,
     fragments stripped; paths are case-sensitive, matching GitHub).
  2. `file.md#anchor` links point at a heading that exists in the target
     file, using GitHub's anchor algorithm (spaces -> hyphens, punctuation
     stripped, unique duplicates get -1/-2 suffixes).
  3. Same-page `#anchor` links resolve against the current file.

Run:  python3 scripts/check_doc_links.py        (from the repo root)
Or:   npm run check:docs
"""

import os
import re
import sys
import unicodedata
import urllib.parse

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

LINK_RE = re.compile(r"\[[^\]]*\]\(\s*(<[^>]*>|[^)\s]+)[^)]*\)")
# Inline/reference image or link definitions: just the parenthesised target.
IMAGE_RE = re.compile(r"!\[[^\]]*\]\(\s*([^)\s]+)[^)]*\)")

MARKDOWN_MEDIA_EXTS = {
    ".md", ".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg",
    ".mp4", ".webm", ".mov", ".pdf",
}


def iter_markdown_files():
    yield os.path.join(ROOT, "README.md")
    docs_dir = os.path.join(ROOT, "docs")
    for dirpath, _dirnames, filenames in os.walk(docs_dir):
        for name in sorted(filenames):
            if name.lower().endswith(".md"):
                yield os.path.join(dirpath, name)


def github_anchor(heading_text):
    """Approximate GitHub's markdown anchor algorithm."""
    text = heading_text.strip().lower()
    # Remove markdown emphasis/link syntax remnants from the raw heading.
    text = re.sub(r"[*_`]", "", text)
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)
    # GitHub keeps CJK/unicode word characters; ASCII punctuation is dropped.
    out = []
    for ch in text:
        cat = unicodedata.category(ch)
        if ch == " ":
            out.append("-")
        elif ch == "-" or cat.startswith(("L", "N", "M")):
            out.append(ch)
        # everything else (punctuation, symbols) is dropped
    return "".join(out)


def collect_anchors(md_path):
    """Set of GitHub-style anchors for every ATX heading in a markdown file."""
    anchors = set()
    seen = {}
    with open(md_path, encoding="utf-8") as fh:
        for line in fh:
            m = re.match(r"^\s{0,3}(#{1,6})\s+(.*?)\s*#*\s*$", line)
            if not m:
                continue
            base = github_anchor(m.group(2))
            if not base:
                continue
            count = seen.get(base, 0)
            seen[base] = count + 1
            anchors.add(base if count == 0 else f"{base}-{count}")
    return anchors


def parse_link_target(raw):
    """Split a raw link target into (path_or_empty, fragment), decoded."""
    target = raw.strip()
    if target.startswith("<") and target.endswith(">"):
        target = target[1:-1]
    path, _, fragment = target.partition("#")
    return urllib.parse.unquote(path), fragment


def check_file(md_path, problems):
    rel = os.path.relpath(md_path, ROOT)
    base_dir = os.path.dirname(md_path)
    with open(md_path, encoding="utf-8") as fh:
        text = fh.read()
    page_anchors = collect_anchors(md_path)

    for m in LINK_RE.finditer(text):
        raw = m.group(1)
        path, fragment = parse_link_target(raw)
        if not path:
            # Same-page anchor link (possibly with only a fragment).
            if fragment and fragment not in page_anchors:
                problems.append(f"{rel}: same-page anchor '#{fragment}' not found")
            continue
        if re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*:", path) or path.startswith("//"):
            continue  # absolute URL — out of scope
        if path.startswith("/"):
            resolved = os.path.join(ROOT, path.lstrip("/"))
        else:
            resolved = os.path.normpath(os.path.join(base_dir, path))
        if not os.path.exists(resolved):
            problems.append(f"{rel}: broken link '({raw})' -> {path}")
            continue
        if fragment and resolved.lower().endswith(".md"):
            if fragment not in collect_anchors(resolved):
                problems.append(
                    f"{rel}: anchor '#{fragment}' not found in {os.path.relpath(resolved, ROOT)}"
                )


def main():
    problems = []
    files = list(iter_markdown_files())
    if not files:
        print("no markdown files found — nothing to check")
        return 1
    for md_path in files:
        check_file(md_path, problems)
    checked = len(files)
    if problems:
        print(f"docs link check FAILED — {len(problems)} problem(s) in {checked} markdown files:\n")
        for p in problems:
            print(f"  - {p}")
        return 1
    print(f"docs link check passed — {checked} markdown files, all relative links and anchors resolve")
    return 0


if __name__ == "__main__":
    sys.exit(main())
