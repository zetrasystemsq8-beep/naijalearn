from pathlib import Path
import re

for f in Path("lib").glob("questions_*.dart"):
    print("Fixing:", f)

    text = f.read_text(encoding="utf-8")

    lines = []

    for line in text.splitlines():

        # Fix question strings
        if '"question":"' in line and ',"options"' in line:
            line = re.sub(
                r'"question":"(.*?)","options"',
                lambda m: '"question":"' + m.group(1).replace('"', '\\"') + '","options"',
                line
            )

        # Fix explanation strings
        if '"explanation":"' in line and '"}' in line:
            line = re.sub(
                r'"explanation":"(.*?)"}',
                lambda m: '"explanation":"' + m.group(1).replace('"', '\\"') + '"}',
                line
            )

        # Fix option arrays
        if '"options":[' in line and '],"correctIndex"' in line:
            start = line.index('"options":[')
            end = line.index('],"correctIndex"')

            options = line[start:end]

            options = options.replace('"', '\\"')
            options = options.replace('\\"options\\"', '"options"')

            line = line[:start] + options + line[end:]

        lines.append(line)

    f.write_text("\n".join(lines), encoding="utf-8")

print("ALL FILES FIXED")


