from pathlib import Path
import re

backup = Path("backup_questions")
lib = Path("lib")

subjects = {
    "accounting": "accountingQuestions",
    "arabic": "arabicQuestions",
    "biology": "biologyQuestions",
    "chemistry": "chemistryQuestions",
    "commerce": "commerceQuestions",
    "crs": "crsQuestions",
    "economics": "economicsQuestions",
    "english": "englishQuestions",
    "geography": "geographyQuestions",
    "government": "governmentQuestions",
    "irs": "irsQuestions",
    "literature": "literatureQuestions",
    "mathematics": "mathematicsQuestions",
    "physics": "physicsQuestions",
}


def fix_quotes(text):
    # Convert double quotes inside Dart strings safely
    text = text.replace('\\"', '"')

    # Escape apostrophes inside single quoted strings
    text = re.sub(
        r"(?<!\\)'([^']*?'[^']*?)'",
        lambda m: '"' + m.group(1).replace('"', '\\"') + '"',
        text
    )

    return text


for name, variable in subjects.items():

    source = backup / f"questions_{name}.dart"
    target = lib / f"questions_{name}.dart"

    if not source.exists():
        print("Missing:", source)
        continue

    content = source.read_text(encoding="utf-8")

    # Keep only the list content if old variable exists
    start = content.find("[")
    end = content.rfind("]")

    if start != -1 and end != -1:
        data = content[start:end+1]
    else:
        data = "[]"

    data = fix_quotes(data)

    output = f"""// Auto generated clean question file

final List<Map<String, dynamic>> {variable} = {data};
"""

    target.write_text(output, encoding="utf-8")

    print("Created", target)

print("DONE")
