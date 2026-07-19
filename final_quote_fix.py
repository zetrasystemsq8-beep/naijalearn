from pathlib import Path

for f in Path("lib").glob("questions_*.dart"):
    print("Fixing", f)

    text = f.read_text(encoding="utf-8")

    # Fix common double quote breaks inside string values
    replacements = {
        '"like"': '\\"like\\"',
        '"as"': '\\"as\\"',
        '"time is a thief"': '\\"time is a thief\\"',
        '"the wind whispered"': '\\"the wind whispered\\"',
        '"I have told you a million times"': '\\"I have told you a million times\\"',
        '"buzz"': '\\"buzz\\"',
        '"hiss"': '\\"hiss\\"',
        '"Peter Piper picked"': '\\"Peter Piper picked\\"',
        '"deafening silence"': '\\"deafening silence\\"',
        '"bittersweet"': '\\"bittersweet\\"',
        '"less is more"': '\\"less is more\\"',
    }

    for old, new in replacements.items():
        text = text.replace(old, new)

    # Fix remaining broken apostrophe examples
    text = text.replace("Pilgrim\\'s", "Pilgrim's")
    text = text.replace("Pascal\\'s", "Pascal's")
    text = text.replace("Archimedes\\'", "Archimedes'")

    f.write_text(text, encoding="utf-8")

print("DONE")

