from pathlib import Path
import re

files = list(Path("lib").glob("questions_*.dart"))

for file in files:
    print("Repairing:", file)

    text = file.read_text(encoding="utf-8")

    # Fix old keys
    replacements = {
        "'s'": "'subject'",
        "'y'": "'year'",
        "'q'": "'question'",
        "'o'": "'options'",
        "'ci'": "'correctIndex'",
        "'e'": "'explanation'",
    }

    for a, b in replacements.items():
        text = text.replace(a + ":", b + ":")

    # Convert single quoted field values to double quotes
    fields = [
        "subject",
        "question",
        "explanation"
    ]

    for field in fields:
        pattern = r"'" + field + r"':'(.*?)'"
        def fix(match):
            value = match.group(1)
            value = value.replace('"', '\\"')
            return '"' + field + '":"' + value + '"'
        text = re.sub(pattern, fix, text, flags=re.S)

    # Fix common apostrophe breaks
    fixes = {
        "Nigeria's": "Nigeria\\'s",
        "Pilgrim's": "Pilgrim\\'s",
        "Pascal's": "Pascal\\'s",
        "Archimedes'": "Archimedes\\'",
    }

    for old, new in fixes.items():
        text = text.replace(old, new)

    file.write_text(text, encoding="utf-8")

print("DONE")

