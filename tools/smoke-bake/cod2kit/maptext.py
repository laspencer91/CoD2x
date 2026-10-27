"""Valve-map token inspection and serialization shared by editor helpers and checks."""

import re


def read(text, spans=False):
    tokens = list(
        re.finditer(r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*[\s\S]*?\*/|[{}]|[^\s{}"]+', text)
    )
    depth = 0
    result = []
    entity = None
    pending = None
    for match in tokens:
        token = match.group()
        if token.startswith(("//", "/*")):
            continue
        if token == "{":
            depth += 1
            if depth == 1:
                entity = {"keys": {}, "brushes": 0, "patches": 0, "origin_brushes": 0}
                if spans:
                    entity.update(
                        start=match.start(),
                        line=text.count("\n", 0, match.start()) + 1,
                        brush_spans=[],
                        patch_spans=[],
                        geometry_spans=[],
                        key_spans={},
                    )
                pending = None
            elif depth == 2:
                if pending is not None:
                    raise ValueError("Entity property is missing its value")
                origin = False
                is_patch = False
                if spans:
                    brush_start = match.start()
        elif token == "}":
            if depth == 2:
                entity["patches" if is_patch else "brushes"] += 1
                if spans:
                    span = (brush_start, match.end())
                    entity["geometry_spans"].append(span)
                    entity["patch_spans" if is_patch else "brush_spans"].append(span)
                if origin and not is_patch:
                    entity["origin_brushes"] += 1
            elif depth == 1:
                if pending is not None:
                    raise ValueError("Entity property is missing its value")
                if spans:
                    entity["end"] = match.end()
                result.append(entity)
            depth -= 1
        elif depth == 1 and token.startswith('"'):
            value = re.sub(r'\\(["\\])', r"\1", token[1:-1])
            if pending is None:
                pending = value
                key_start = match.start()
            else:
                if pending in entity["keys"]:
                    raise ValueError("Duplicate entity property: " + pending)
                entity["keys"][pending] = value
                if spans:
                    entity["key_spans"][pending] = (key_start, match.end())
                pending = None
        elif depth == 2 and token.startswith("patchDef"):
            is_patch = True
        elif depth == 2 and token in ("cod2/origin", "tools/origin", "origin"):
            origin = True
        if depth < 0:
            raise ValueError("Unbalanced map entity braces")
    if depth or pending is not None:
        raise ValueError("Incomplete map entity")
    return result


def quote(value):
    text = str(value)
    if any(c in text for c in "\r\n\0"):
        raise ValueError("Map property values cannot contain line breaks or NUL")
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def replace_world_keys(text, values):
    entities = read(text, spans=True)
    if not entities or entities[0]["keys"].get("classname") != "worldspawn":
        raise ValueError("Map needs worldspawn as its first entity")
    world = entities[0]
    edits = []
    new = []
    for key, value in values.items():
        line = f"{quote(key)} {quote(value)}"
        span = world["key_spans"].get(key)
        if span:
            edits.append((*span, line))
        else:
            new.append(line)
    if new:
        at = (
            world["geometry_spans"][0][0]
            if world["geometry_spans"]
            else world["end"] - 1
        )
        edits.append((at, at, "\n" + "\n".join(new) + "\n"))
    for start, end, replacement in sorted(edits, reverse=True):
        text = text[:start] + replacement + text[end:]
    return text


def box(lo, hi, material):
    x, y, z = lo
    a, b, c = hi
    sides = [
        ((x, y, z), (x, y + 1, z), (x, y, z + 1), "0 1 0", "0 0 -1"),
        ((x, y, z), (x, y, z + 1), (x + 1, y, z), "1 0 0", "0 0 -1"),
        ((x, y, z), (x + 1, y, z), (x, y + 1, z), "1 0 0", "0 -1 0"),
        ((a, b, c), (a, b + 1, c), (a + 1, b, c), "1 0 0", "0 -1 0"),
        ((a, b, c), (a + 1, b, c), (a, b, c + 1), "1 0 0", "0 0 -1"),
        ((a, b, c), (a, b, c + 1), (a, b + 1, c), "0 1 0", "0 0 -1"),
    ]
    return (
        "{\n"
        + "".join(
            " ".join("( {} )".format(" ".join(map(str, p))) for p in (p0, p1, p2))
            + f" {material} [ {u} 0 ] [ {v} 0 ] 0 1 1\n"
            for p0, p1, p2, u, v in sides
        )
        + "}\n"
    )


def entity_text(keys, brushes=()):
    return (
        "{\n"
        + "".join(f"{quote(k)} {quote(v)}\n" for k, v in keys.items())
        + "".join(brushes)
        + "}\n"
    )


def point(cls, origin, **keys):
    values = {"classname": cls, "origin": " ".join(map(str, origin))} | keys
    return entity_text(values)
