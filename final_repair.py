from pathlib import Path
import re

files = list(Path("lib").glob("questions_*.dart"))

for f in files:
    print("Repairing:", f)

    text = f.read_text(encoding="utf-8")

    # Fix keys
    replacements = {
        "'s'": "'subject'",
        "'y'": "'year'",
        "'q'": "'question'",
        "'o'": "'options'",
        "'ci'": "'correctIndex'",
        "'e'": "'explanation'",
    }

    for a,b in replacements.items():
        text = text.replace(a,b)

    # Convert every single quoted Dart string safely
    def fix_string(match):
        content = match.group(1)

        # escape existing double quotes
        content = content.replace('"', '\\"')

        # remove bad escaping then restore apostrophes
        return '"' + content + '"'

    # only fix values after : and inside lists
    text = re.sub(r"'([^'\n]*(?:'[^'\n]*)*)'", fix_string, text)

    f.write_text(text, encoding="utf-8")

print("FINAL COMPLETE")

