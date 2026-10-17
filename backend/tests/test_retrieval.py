import unittest
from unittest.mock import patch

from repo_context import (
    CodeChunk,
    build_repo_context,
    search_code_chunks,
)
from llm_service import (
    NO_MATCH_ANSWER,
    ask_question,
    stream_question,
)


class RetrievalTests(unittest.IsolatedAsyncioTestCase):
    def test_more_matching_terms_rank_first(self):
        general = CodeChunk("a.swift", 1, 1, "Task { }")
        specific = CodeChunk(
            "b.swift",
            10,
            10,
            "guard !Task.isCancelled else { return }",
        )

        with patch(
            "repo_context.load_code_chunks",
            return_value=[general, specific],
        ):
            result = search_code_chunks(
                "Task.isCancelled",
                top_k=1,
            )

        self.assertEqual(result, [specific])

    def test_context_preserves_original_line_numbers(self):
        chunk = CodeChunk(
            "sample.swift",
            33,
            34,
            "let value = 1\nprint(value)",
        )

        context = build_repo_context([chunk])

        self.assertIn("sample.swift:L33-L34", context)
        self.assertIn(
            "33: let value = 1\n34: print(value)",
            context,
        )

    async def test_no_match_does_not_call_model(self):
        chunk = CodeChunk(
            "sample.swift",
            1,
            1,
            "let value = 1",
        )

        with patch(
            "repo_context.load_code_chunks",
            return_value=[chunk],
        ):
            chunks = search_code_chunks("向量数据库")
            self.assertEqual(chunks, [])

            with patch("llm_service.create_model") as create_model:
                response = await ask_question("向量数据库")

                parts = []
                async for text in stream_question(
                    "向量数据库",
                    chunks,
                ):
                    parts.append(text)

                self.assertEqual(response.content, NO_MATCH_ANSWER)
                self.assertEqual("".join(parts), NO_MATCH_ANSWER)
                create_model.assert_not_called()