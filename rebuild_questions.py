from pathlib import Path
import ast
import re

for file in Path("lib").glob("questions_*.dart"):
    print("Repairing", file)

    lines = file.read_text(encoding="utf-8").splitlines()
    out = []

    for line in lines:
        if "{'s':" not in line:
            out.append(line)
            continue

        # Replace keys
        line = line.replace("'s':", "'subject':")
        line = line.replace("'y':", "'year':")
        line = line.replace("'q':", "'question':")
        line = line.replace("'o':", "'options':")
        line = line.replace("'ci':", "'correctIndex':")
        line = line.replace("'e':", "'explanation':")

        # Convert all single quotes to double quotes safely
        line = line.replace("\\'", "'")

        # Protect apostrophes
        line = line.replace("Nigeria's", "Nigeria\\'s")
        line = line.replace("Pilgrim's", "Pilgrim\\'s")
        line = line.replace("Pascal's", "Pascal\\'s")
        line = line.replace("Archimedes'", "Archimedes\\'")

        # Make Dart double quoted strings
        line = line.replace("'", '"')

        out.append(line)

    file.write_text("\n".join(out), encoding="utf-8")

print("COMPLETE")

