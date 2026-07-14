#!/usr/bin/env python3
"""Flag function calls in a Lua file that are neither Codea built-ins nor
defined in the project — a cheap first-pass check for invented API names
before wasting a build-and-test cycle.

Usage:
    python3 check_codea_api_calls.py <file.lua> <codea-api-globals.txt> [other_project_file.lua ...]

Extra project files contribute *definitions only* (functions defined in
other Codea tabs won't be falsely flagged) — only the first file is checked.

Not a Lua parser: plain text matching. Method calls (obj:foo()) are not
checked. Exit code 1 if anything is flagged, 0 otherwise.
"""
import re
import sys

LUA_KEYWORDS = {
    "and", "break", "do", "else", "elseif", "end", "false", "for",
    "function", "goto", "if", "in", "local", "nil", "not", "or",
    "repeat", "return", "then", "true", "until", "while",
}


def strip_comments_and_strings(src: str) -> str:
    """Replace comments and string contents with spaces, preserving line
    numbers, so matches inside them are ignored."""
    out = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        # long bracket (string or comment): [[ ]] / [=[ ]=] , --[[ ]]
        is_comment = src.startswith("--", i)
        j = i + 2 if is_comment else i
        m = re.match(r"\[(=*)\[", src[j:]) if j < n else None
        if (is_comment or c == "[") and m:
            close = "]" + m.group(1) + "]"
            end = src.find(close, j + m.end())
            end = n if end == -1 else end + len(close)
            out.append(re.sub(r"[^\n]", " ", src[i:end]))
            i = end
        elif is_comment:  # line comment
            end = src.find("\n", i)
            end = n if end == -1 else end
            out.append(" " * (end - i))
            i = end
        elif c in "'\"":
            j = i + 1
            while j < n and src[j] != c:
                j += 2 if src[j] == "\\" else 1
            j = min(j + 1, n)
            out.append(re.sub(r"[^\n]", " ", src[i:j]))
            i = j
        else:
            out.append(c)
            i += 1
    return "".join(out)


def load_globals(path: str):
    """Reference file: one 'name : type' (or bare name) per line.
    May contain one-level dotted entries like 'math.floor : function'."""
    full, roots_with_children = set(), set()
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            name = line.split(":")[0].strip()
            if not re.fullmatch(r"[A-Za-z_]\w*(\.[A-Za-z_]\w*)*", name or ""):
                continue
            full.add(name)
            if "." in name:
                roots_with_children.add(name.split(".")[0])
    return full, roots_with_children


def collect_definitions(cleaned: str) -> set:
    defined = set()
    # function foo(...) / function foo.bar(...) / function foo:bar(...)
    for m in re.finditer(r"\bfunction\s+([A-Za-z_][\w.:]*)\s*\(([^)]*)\)", cleaned):
        name = m.group(1)
        defined.add(name.replace(":", "."))
        defined.add(name.split(".")[0].split(":")[0])
        for p in m.group(2).split(","):
            p = p.strip()
            if re.fullmatch(r"[A-Za-z_]\w*", p):
                defined.add(p)
    # local function foo / anonymous assigned params handled above
    # assignments: foo = ..., local foo, bar = ...
    for m in re.finditer(r"^\s*(?:local\s+)?([A-Za-z_][\w.,\s]*?)\s*=", cleaned, re.M):
        for name in m.group(1).split(","):
            name = name.strip()
            if re.fullmatch(r"[A-Za-z_]\w*(\.[A-Za-z_]\w*)*", name):
                defined.add(name)
                defined.add(name.split(".")[0])
    # local declarations without assignment, and for-loop variables
    for m in re.finditer(r"\b(?:local|for)\s+([A-Za-z_]\w*(?:\s*,\s*[A-Za-z_]\w*)*)", cleaned):
        for name in m.group(1).split(","):
            defined.add(name.strip())
    return defined


CALL_RE = re.compile(r"(?<![\w.:\"'])([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\s*\(")


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    target, globals_path, extra = sys.argv[1], sys.argv[2], sys.argv[3:]

    globals_full, roots_with_children = load_globals(globals_path)
    with open(target, encoding="utf-8", errors="replace") as f:
        cleaned = strip_comments_and_strings(f.read())
    defined = collect_definitions(cleaned)
    for path in extra:
        with open(path, encoding="utf-8", errors="replace") as f:
            defined |= collect_definitions(strip_comments_and_strings(f.read()))

    flagged = {}
    for lineno, line in enumerate(cleaned.splitlines(), 1):
        for m in CALL_RE.finditer(line):
            name = m.group(1)
            root = name.split(".")[0]
            if root in LUA_KEYWORDS or name in defined or root in defined:
                continue
            if name in globals_full:
                continue
            if "." in name:
                if root in roots_with_children:
                    # we know this table's members; this one isn't among them
                    flagged.setdefault(name, []).append(lineno)
                elif root in globals_full:
                    continue  # known table, members not enumerated — can't verify
                else:
                    flagged.setdefault(name, []).append(lineno)
            else:
                flagged.setdefault(name, []).append(lineno)

    if flagged:
        print(f"{target}: {len(flagged)} unrecognized call name(s):")
        for name in sorted(flagged):
            lines = ",".join(map(str, flagged[name][:8]))
            print(f"  {name}  (line {lines})")
        print("Check each: genuine miss in the reference list, a global from "
              "another tab not passed as an extra arg, or an invented API call.")
        sys.exit(1)
    print(f"{target}: OK — all call names recognized.")


if __name__ == "__main__":
    main()