"""Fail if an app class has no deinit of its own.

The app builds with SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor, so Swift gives every class
without a deinit a main-actor one. That one aborts on macOS 15 and crashes the Xcode 26.6
Release compile. Add `nonisolated deinit {}` to the class named below.
"""
import pathlib, re, sys

DECL = re.compile(r'^[ \t]*(?:@[\w.]+(?:\([^)]*\))?\s+)*(?:(?:public|private|fileprivate|internal|open|final|nonisolated)\s+)*'
                  r'class\s+(?!(?:func|var|let|subscript)\b)([A-Za-z_]\w*)\b')
# A real deinit line, not a comment that mentions the word.
DEINIT = re.compile(r'(?:^|[\s{;])(?:nonisolated\s+)?deinit\s*\{')
missing = []
for f in sorted(pathlib.Path(sys.argv[1]).rglob("*.swift")):
    lines = f.read_text().split("\n")
    starts = [i for i, l in enumerate(lines) if DECL.match(l) and not l.lstrip().startswith("//")]
    for n, i in enumerate(starts):
        body = lines[i:starts[n + 1] if n + 1 < len(starts) else len(lines)]
        # shortcut: a class's body runs to the next class declaration, so its deinit must come before
        # any nested class (the inserted one sits on the first line of every class body).
        if not any(DEINIT.search(l.split("//")[0]) for l in body):
            missing.append(f"{f}:{i + 1}: class {DECL.match(lines[i]).group(1)} has no deinit")
print("\n".join(missing) or "Every class has its own deinit.")
sys.exit(1 if missing else 0)
