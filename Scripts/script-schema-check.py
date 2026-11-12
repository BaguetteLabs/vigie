#!/usr/bin/env python3
"""Validates the script-schema fixtures against schemas/script-module.schema.json (Story 12.1, AD-16, AD-18).

No JSON Schema library is allowed (AD-16) and CI has none, so this is a small validator for the subset of
JSON Schema 2020-12 the schema uses: type, enum, const, required, properties, additionalProperties, items,
oneOf, minimum, exclusiveMinimum, maximum, minLength, minItems, uniqueItems, pattern and $ref within the file.
Any other keyword in the schema is an error, so the subset cannot drift silently.

Fixtures live in Packages/Modules/Integrations/Tests/IntegrationsTests/Fixtures/script-schema/{valid,invalid}.
Each is {"description", "kind": "front-matter" | "output", "document", "error"?}; the Swift test
(ScriptSchemaFixtureTests) reads the same files, so both sides agree on every valid/invalid outcome.
The check also fails when a valid fixture set leaves a declared property, enum value or oneOf branch
unexercised.

Usage: python3 -I Scripts/script-schema-check.py [--schema PATH] [--fixtures DIR]
"""

import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCHEMA = os.path.join(ROOT, "schemas", "script-module.schema.json")
FIXTURES = os.path.join(
    ROOT, "Packages", "Modules", "Integrations", "Tests", "IntegrationsTests", "Fixtures", "script-schema"
)
KINDS = {"front-matter": "#/$defs/frontMatter", "output": "#/$defs/output"}

ANNOTATIONS = {"$schema", "$id", "$defs", "$comment", "title", "description", "default", "examples"}
ASSERTIONS = {
    "type", "enum", "const", "required", "properties", "additionalProperties", "items", "oneOf",
    "minimum", "exclusiveMinimum", "maximum", "minLength", "minItems", "uniqueItems", "pattern", "$ref",
}


class Validator:
    def __init__(self, schema):
        self.schema = schema
        self.coverage = set()  # what valid documents exercised: ("prop", ptr, name), ("enum", ptr, value), ...
        self.recording = False

    def resolve(self, ref):
        if not ref.startswith("#/"):
            raise SystemExit(f"error: only in-file $ref is supported: {ref}")
        node = self.schema
        for part in ref[2:].split("/"):
            node = node[part.replace("~1", "/").replace("~0", "~")]
        return node

    def check_keywords(self, node, ptr):
        """Every keyword in the schema must be one this validator implements or an annotation."""
        if isinstance(node, bool):
            return
        for key, value in node.items():
            if key not in ANNOTATIONS | ASSERTIONS:
                raise SystemExit(f"error: {ptr}: keyword '{key}' is outside the supported subset")
        for key in ("properties", "$defs"):
            for name, sub in node.get(key, {}).items():
                self.check_keywords(sub, f"{ptr}/{key}/{name}")
        for i, sub in enumerate(node.get("oneOf", [])):
            self.check_keywords(sub, f"{ptr}/oneOf/{i}")
        for key in ("items", "additionalProperties"):
            if isinstance(node.get(key), dict):
                self.check_keywords(node[key], f"{ptr}/{key}")

    def declared(self, node, ptr, out, seen):
        """Collects every coverage target reachable from a schema node."""
        if isinstance(node, bool) or ptr in seen:
            return
        seen.add(ptr)
        if "$ref" in node:
            self.declared(self.resolve(node["$ref"]), node["$ref"], out, seen)
        if "enum" in node and len(node["enum"]) > 1:
            for value in node["enum"]:
                out.add(("enum", ptr, json.dumps(value)))
        for name, sub in node.get("properties", {}).items():
            out.add(("prop", ptr, name))
            self.declared(sub, f"{ptr}/properties/{name}", out, seen)
        for i, sub in enumerate(node.get("oneOf", [])):
            out.add(("oneOf", ptr, i))
            self.declared(sub, f"{ptr}/oneOf/{i}", out, seen)
        if isinstance(node.get("items"), dict):
            self.declared(node["items"], f"{ptr}/items", out, seen)

    @staticmethod
    def type_ok(value, name):
        if name == "null":
            return value is None
        if name == "boolean":
            return isinstance(value, bool)
        if name == "integer":
            return (isinstance(value, int) and not isinstance(value, bool)) or (
                isinstance(value, float) and value.is_integer()
            )
        if name == "number":
            return isinstance(value, (int, float)) and not isinstance(value, bool)
        if name == "string":
            return isinstance(value, str)
        if name == "array":
            return isinstance(value, list)
        if name == "object":
            return isinstance(value, dict)
        raise SystemExit(f"error: unknown type '{name}'")

    @staticmethod
    def equal(a, b):
        return json.dumps(a, sort_keys=True) == json.dumps(b, sort_keys=True) and (
            isinstance(a, bool) == isinstance(b, bool)
        )

    @staticmethod
    def pattern_matches(pattern, value):
        # ECMA-262 `$` matches only at the end; Python's also matches before a final newline.
        if pattern.endswith("$") and not pattern.endswith("\\$"):
            pattern = pattern[:-1] + r"\Z"
        return re.search(pattern, value) is not None

    def validate(self, node, value, ptr, path, errors):
        """Appends "<path>: <message>" for every failure; records coverage while self.recording."""
        if node is True:
            return
        if node is False:
            errors.append(f"{path}: not allowed")
            return
        if "$ref" in node:
            self.validate(self.resolve(node["$ref"]), value, node["$ref"], path, errors)
        if "type" in node:
            names = node["type"] if isinstance(node["type"], list) else [node["type"]]
            if not any(self.type_ok(value, n) for n in names):
                errors.append(f"{path}: expected {' or '.join(names)}")
                return
        if "const" in node and not self.equal(value, node["const"]):
            errors.append(f"{path}: must be {json.dumps(node['const'])}")
        if "enum" in node:
            if not any(self.equal(value, option) for option in node["enum"]):
                errors.append(f"{path}: {json.dumps(value)} is not one of {node['enum']}")
            elif self.recording:
                self.coverage.add(("enum", ptr, json.dumps(value)))
        if isinstance(value, str):
            if "minLength" in node and len(value) < node["minLength"]:
                errors.append(f"{path}: shorter than {node['minLength']}")
            if "pattern" in node and not self.pattern_matches(node["pattern"], value):
                errors.append(f"{path}: does not match {node['pattern']}")
        if isinstance(value, (int, float)) and not isinstance(value, bool):
            if "minimum" in node and value < node["minimum"]:
                errors.append(f"{path}: below {node['minimum']}")
            if "exclusiveMinimum" in node and value <= node["exclusiveMinimum"]:
                errors.append(f"{path}: must be above {node['exclusiveMinimum']}")
            if "maximum" in node and value > node["maximum"]:
                errors.append(f"{path}: above {node['maximum']}")
        if isinstance(value, list):
            if "minItems" in node and len(value) < node["minItems"]:
                errors.append(f"{path}: fewer than {node['minItems']} items")
            if node.get("uniqueItems"):
                dumped = [json.dumps(v, sort_keys=True) for v in value]
                if len(set(dumped)) != len(dumped):
                    errors.append(f"{path}: items are not unique")
            if "items" in node:
                for i, item in enumerate(value):
                    self.validate(node["items"], item, f"{ptr}/items", f"{path}[{i}]", errors)
        if isinstance(value, dict):
            for name in node.get("required", []):
                if name not in value:
                    child = f"{path}.{name}" if path else name
                    errors.append(f"{child}: missing required key '{name}'")
            props = node.get("properties", {})
            for name, item in value.items():
                child = f"{path}.{name}" if path else name
                if name in props:
                    if self.recording:
                        self.coverage.add(("prop", ptr, name))
                    self.validate(props[name], item, f"{ptr}/properties/{name}", child, errors)
                elif "additionalProperties" in node:
                    self.validate(node["additionalProperties"], item, f"{ptr}/additionalProperties", child, errors)
        if "oneOf" in node:
            matches = []
            for i, branch in enumerate(node["oneOf"]):
                branch_errors = []
                saved = self.recording
                self.recording = False
                self.validate(branch, value, f"{ptr}/oneOf/{i}", path, branch_errors)
                self.recording = saved
                if not branch_errors:
                    matches.append(i)
            if len(matches) != 1:
                errors.append(f"{path}: matches {len(matches)} of the oneOf alternatives, expected exactly 1")
            elif self.recording:
                i = matches[0]
                self.coverage.add(("oneOf", ptr, i))
                self.validate(node["oneOf"][i], value, f"{ptr}/oneOf/{i}", path, [])


def covers(path, wanted):
    """True when `path` is `wanted` or an object or array above it (the document itself counts only for itself)."""
    if path == wanted:
        return True
    return path != "" and (wanted.startswith(path + ".") or wanted.startswith(path + "["))


def main(argv):
    schema_path, fixtures = SCHEMA, FIXTURES
    args = list(argv)
    while args:
        flag = args.pop(0)
        if flag == "--schema":
            schema_path = args.pop(0)
        elif flag == "--fixtures":
            fixtures = args.pop(0)
        else:
            raise SystemExit(f"usage: script-schema-check.py [--schema PATH] [--fixtures DIR] (got {flag})")

    with open(schema_path, encoding="utf-8") as handle:
        schema = json.load(handle)
    validator = Validator(schema)
    validator.check_keywords(schema, "#")

    failures = []
    counts = {}
    for expect in ("valid", "invalid"):
        folder = os.path.join(fixtures, expect)
        names = sorted(n for n in os.listdir(folder) if n.endswith(".json"))
        if not names:
            failures.append(f"{expect}: no fixtures")
        for name in names:
            with open(os.path.join(folder, name), encoding="utf-8") as handle:
                fixture = json.load(handle)
            kind = fixture.get("kind")
            if kind not in KINDS or "document" not in fixture:
                failures.append(f"{expect}/{name}: needs 'kind' ({' | '.join(KINDS)}) and 'document'")
                continue
            if expect == "invalid" and not fixture.get("error"):
                failures.append(f"{expect}/{name}: an invalid fixture names the offending key in 'error'")
            counts[(expect, kind)] = counts.get((expect, kind), 0) + 1
            errors = []
            validator.recording = expect == "valid"
            validator.validate({"$ref": KINDS[kind]}, fixture["document"], "#", "", errors)
            validator.recording = False
            if expect == "valid" and errors:
                failures.append(f"valid/{name}: rejected by the schema: {'; '.join(errors)}")
            if expect == "invalid" and not errors:
                failures.append(f"invalid/{name}: accepted by the schema")
            elif expect == "invalid" and fixture.get("error"):
                # The schema must fail at the named key or at an object above it (a oneOf reports its parent).
                wanted = "" if fixture["error"] == "(document)" else fixture["error"]
                paths = [e.split(": ", 1)[0] for e in errors]
                if not any(covers(p, wanted) for p in paths):
                    failures.append(f"invalid/{name}: rejected at {paths}, not at '{wanted}'")

    declared = set()
    for ref in KINDS.values():
        validator.declared({"$ref": ref}, "#", declared, set())
    for target in sorted(declared - validator.coverage, key=str):
        kind, ptr, what = target
        failures.append(f"coverage: no valid fixture exercises {kind} {what} at {ptr}")

    summary = ", ".join(f"{e} {k}: {n}" for (e, k), n in sorted(counts.items()))
    if failures:
        for line in failures:
            print(f"error: {line}", file=sys.stderr)
        print(f"script-schema check: FAILED ({summary})", file=sys.stderr)
        return 1
    print(f"script-schema check: OK ({summary})")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
