from pathlib import Path
import re

for f in Path("lib").glob("questions_*.dart"):
    print("Repairing", f)

    text = f.read_text(encoding="utf-8")

    # Fix short keys only
    text = text.replace("'s':", "'subject':")
    text = text.replace("'y':", "'year':")
    text = text.replace("'q':", "'question':")
    text = text.replace("'o':", "'options':")
    text = text.replace("'ci':", "'correctIndex':")
    text = text.replace("'e':", "'explanation':")

    # Escape apostrophe problems inside single strings
    text = text.replace("\\'", "'")
    
    # Convert only apostrophes inside words
    text = re.sub(r"([A-Za-z])'([A-Za-z])", r"\1\\'\2", text)

    f.write_text(text, encoding="utf-8")

print("DONE")
