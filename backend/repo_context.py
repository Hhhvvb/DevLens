import re

from pathlib import Path
from dataclasses import dataclass

PROJECT_ROOT = Path(__file__).resolve().parent.parent

SOURCE_FILES = (
    "backend/main.py",
    "ios/DevLens/DevLens/APIClient.swift",
    "ios/DevLens/DevLens/QuestionViewModel.swift",
)

@dataclass(frozen=True)
class CodeChunk:
    path: str
    start_line: int
    end_line: int
    content: str

def build_repo_context(chunks: list[CodeChunk]) -> str:
    sections: list[str] = []

    for chunk in chunks:
        numbered_lines: list[str] = []

        for number, line in enumerate(
            chunk.content.splitlines(),
            start=chunk.start_line,
        ):
            numbered_lines.append(f"{number}: {line}")

        numbered_content = "\n".join(numbered_lines)

        sections.append(
            f"文件：{chunk.path}:L{chunk.start_line}-L{chunk.end_line}\n"
            f"```text\n{numbered_content}\n```"
        )

    return "\n\n".join(sections)

def load_code_chunks() -> list[CodeChunk]:
    chunks: list[CodeChunk] = []

    chunk_size = 40
    overlap = 8
    step = chunk_size - overlap

    for relative_path in SOURCE_FILES:
        file_path = PROJECT_ROOT / relative_path
        lines = file_path.read_text(
            encoding="utf-8"
        ).splitlines()

        for start in range(0, len(lines), step):
            end = min(start + chunk_size, len(lines))
            content = "\n".join(lines[start:end])

            chunks.append(
                CodeChunk(
                    path=relative_path,
                    start_line=start + 1,
                    end_line=end,
                    content=content
                )
            )

            if end == len(lines):
                break

    return chunks

def tokenize_for_search(text: str) -> set[str]:
    tokens = set(
        re.findall(r"[a-z_][a-z0-9_]*", text.lower())
    )

    chinese_phrases = re.findall(
        r"[\u4e00-\u9fff]+",
        text,
    )

    for phrase in chinese_phrases:
        for index in range(len(phrase) - 1):
            tokens.add(phrase[index:index + 2])

    return tokens

def search_code_chunks(
    question: str,
    top_k: int = 3,
    chunks: list[CodeChunk] | None = None,
) -> list[CodeChunk]:
    if top_k <= 0:
        raise ValueError("top_k 必须大于 0")

    query_tokens = tokenize_for_search(question)

    if not query_tokens:
        return []

    if chunks is None:
        chunks = load_code_chunks()

    scored_chunks: list[tuple[int, CodeChunk]] = []

    for chunk in chunks:
        searchable_text = f"{chunk.path}\n{chunk.content}"
        chunk_tokens = tokenize_for_search(searchable_text)

        matched_tokens = query_tokens & chunk_tokens
        score = len(matched_tokens)

        if score > 0:
            scored_chunks.append((score, chunk))

    scored_chunks.sort(
        key=lambda item: item[0],
        reverse=True,
    )

    return [
        chunk
        for score, chunk in scored_chunks[:top_k]
    ]
