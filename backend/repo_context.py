from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent

SOURCE_FILES = (
    "backend/main.py",
    "ios/DevLens/DevLens/APIClient.swift",
    "ios/DevLens/DevLens/QuestionViewModel.swift",
)

def build_repo_context() -> str:
    sections: list[str] = []

    for relative_path in SOURCE_FILES:
        file_path = PROJECT_ROOT / relative_path
        content = file_path.read_text(encoding="utf-8")

        numbered_lines: list[str] = []

        for number, line in enumerate(content.splitlines(), start=1):
            numbered_lines.append(f"{number}: {line}")

        numbered_content = "\n".join(numbered_lines)

        sections.append(
            f"文件: {relative_path}\n"
            f"```text\n{numbered_content}\n```"
        )

    return "\n\n".join(sections)