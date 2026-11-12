#!/usr/bin/env python3
"""Validates the bundled example scripts against schemas/script-module.schema.json (Story 12.7).

For each Packages/Modules/Integrations/Sources/Integrations/Resources/Examples/<name>.md: the front matter
(between the first two `---` lines) validates as #/$defs/frontMatter, the file holds exactly one fenced code
block, and <name>.sample.json (a sample of the script's stdout) validates as #/$defs/output, declares the same
widget type as the front matter and is valid JSON. Stdlib only (no PyYAML in CI): the front matter is read by a
reader for the YAML subset the examples use (scalars, flow lists, and a block list of flow mappings); anything
else fails the check, so an example cannot drift into syntax this reader would misread.

Usage: python3 -I Scripts/check-example-scripts.py [DIR]
"""

import importlib.util
import json
import os
import re
import sys

sys.dont_write_bytecode = True  # importing script-schema-check must not leave a __pycache__
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXAMPLES = os.path.join(ROOT, "Packages", "Modules", "Integrations", "Sources", "Integrations", "Resources", "Examples")

spec = importlib.util.spec_from_file_location("schema_check", os.path.join(ROOT, "Scripts", "script-schema-check.py"))
schema_check = importlib.util.module_from_spec(spec)
spec.loader.exec_module(schema_check)


def scalar(text):
    text = text.strip()
    if len(text) >= 2 and text[0] == text[-1] and text[0] in "\"'":
        return text[1:-1]
    if re.fullmatch(r"-?[0-9]+", text):
        return int(text)
    if text in ("true", "false"):
        return text == "true"
    if re.search(r"[\[\]{}#&*!|>%@`]", text) or ": " in text:
        raise ValueError(f"unsupported YAML scalar: {text}")
    return text


def split_flow(body):
    parts, depth, quote, current = [], 0, None, ""
    for ch in body:
        if quote:
            current += ch
            if ch == quote:
                quote = None
        elif ch in "\"'":
            quote = ch
            current += ch
        elif ch in "[{":
            depth += 1
            current += ch
        elif ch in "]}":
            depth -= 1
            current += ch
        elif ch == "," and depth == 0:
            parts.append(current)
            current = ""
        else:
            current += ch
    if current.strip():
        parts.append(current)
    return parts


def value(text):
    text = text.strip()
    if text.startswith("[") and text.endswith("]"):
        return [value(p) for p in split_flow(text[1:-1])]
    if text.startswith("{") and text.endswith("}"):
        result = {}
        for part in split_flow(text[1:-1]):
            key, _, rest = part.partition(":")
            result[key.strip()] = value(rest)
        return result
    return scalar(text)


def front_matter(lines):
    doc, i = {}, 0
    while i < len(lines):
        line = lines[i]
        i += 1
        if not line.strip():
            continue
        match = re.fullmatch(r"([A-Za-z_]+):(?:\s+(.*))?", line)
        if not match:
            raise ValueError(f"unsupported front matter line: {line}")
        key, rest = match.group(1), match.group(2)
        if rest is None:
            items = []
            while i < len(lines) and lines[i].startswith("  - "):
                items.append(value(lines[i][4:]))
                i += 1
            doc[key] = items
        else:
            doc[key] = value(re.sub(r"\s+#.*$", "", rest))
    return doc


def code_blocks(lines):
    blocks, fence = 0, None
    for line in lines:
        m = re.match(r" {0,3}(`{3,}|~{3,})", line)
        if fence is None and m:
            fence = m.group(1)
            blocks += 1
        elif fence and m and m.group(1)[0] == fence[0] and len(m.group(1)) >= len(fence) and line.strip() == m.group(1):
            fence = None
    return blocks


def main(argv):
    folder = argv[0] if argv else EXAMPLES
    with open(os.path.join(ROOT, "schemas", "script-module.schema.json"), encoding="utf-8") as handle:
        validator = schema_check.Validator(json.load(handle))
    failures, names = [], sorted(n for n in os.listdir(folder) if n.endswith(".md"))
    if len(names) < 3:
        failures.append("fewer than 3 example scripts")
    for name in names:
        stem = name[:-3]
        with open(os.path.join(folder, name), encoding="utf-8") as handle:
            lines = handle.read().split("\n")
        if lines[0] != "---" or "---" not in lines[1:]:
            failures.append(f"{name}: missing front matter")
            continue
        end = lines.index("---", 1)
        try:
            front = front_matter(lines[1:end])
        except ValueError as error:
            failures.append(f"{name}: {error}")
            continue
        errors = []
        validator.validate({"$ref": "#/$defs/frontMatter"}, front, "#", "", errors)
        failures += [f"{name}: front matter: {e}" for e in errors]
        if code_blocks(lines[end + 1:]) != 1:
            failures.append(f"{name}: needs exactly one fenced code block")
        if not any(line.strip() for line in lines[end + 1:] if not line.startswith("`")):
            failures.append(f"{name}: no documentation")
        sample = os.path.join(folder, stem + ".sample.json")
        if not os.path.exists(sample):
            failures.append(f"{stem}.sample.json: missing")
            continue
        try:
            with open(sample, encoding="utf-8") as handle:
                output = json.load(handle)
        except ValueError as error:
            failures.append(f"{stem}.sample.json: not JSON: {error}")
            continue
        errors = []
        validator.validate({"$ref": "#/$defs/output"}, output, "#", "", errors)
        failures += [f"{stem}.sample.json: {e}" for e in errors]
        if isinstance(output, dict) and output.get("widget", {}).get("type") != front.get("widget"):
            failures.append(f"{stem}.sample.json: widget type differs from the front matter's '{front.get('widget')}'")
    if failures:
        for line in failures:
            print(f"error: {line}", file=sys.stderr)
        print("example-scripts check: FAILED", file=sys.stderr)
        return 1
    print(f"example-scripts check: OK ({len(names)} examples)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
