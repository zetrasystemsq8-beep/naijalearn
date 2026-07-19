from pathlib import Path
import re

for f in Path("lib").glob("questions_*.dart"):
    text = f.read_text(encoding="utf-8")

    # Replace field names
    text = text.replace("'s':", "'subject':")
    text = text.replace("'y':", "'year':")
    text = text.replace("'q':", "'question':")
    text = text.replace("'o':", "'options':")
    text = text.replace("'ci':", "'correctIndex':")
    text = text.replace("'e':", "'explanation':")

    # Convert every value to double quotes
    text = re.sub(r"'subject':'([^']*)'", r'"subject":"\1"', text)
    text = re.sub(r"'question':'([^']*)'", r'"question":"\1"', text)
    text = re.sub(r"'explanation':'([^']*)'", r'"explanation":"\1"', text)

    f.write_text(text, encoding="utf-8")
    print("Fixed", f)

