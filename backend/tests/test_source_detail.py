import json
import os
import unittest
from unittest.mock import patch

from fastapi.testclient import TestClient
from main import app
from repo_context import CodeChunk


class SourceDetailsTests(unittest.TestCase):
    def test_done_preserves_chunks_from_same_file(self):
        chunks = [
            CodeChunk(
                "sample.swift",
                10,
                12,
                "let value = 1\n\nprint(value)",
            ),
            CodeChunk(
                "sample.swift",
                20,
                20,
                'let name = "DevLens"',
            ),
        ]

        async def fake_stream(question, selected_chunks):
            yield "测试回答"

        with (
            patch.dict(
                os.environ,
                {"DEEPSEEK_API_KEY": "test-only"},
            ),
            patch(
                "main.CodeRetriever",
            ) as retriever_class,
            patch(
                "main.stream_question",
                side_effect=fake_stream,
            ) as stream_mock,
            TestClient(app) as client,
        ):
            retriever_class.return_value.search.return_value = chunks
            response = client.post(
                "/v1/ask/stream",
                json={"question": "解释这段代码"},
            )

        retriever_class.assert_called_once_with()
        retriever_class.return_value.search.assert_called_once_with(
            "解释这段代码"
        )

        self.assertEqual(response.status_code, 200)
        self.assertIn(
            "text/event-stream",
            response.headers["content-type"],
        )
        stream_mock.assert_called_once_with(
            "解释这段代码",
            chunks,
        )

        events = []

        for block in response.text.strip().split("\n\n"):
            event_line, data_line = block.splitlines()

            events.append((
                event_line.removeprefix("event:").strip(),
                json.loads(data_line.removeprefix("data:")),
            ))

        self.assertEqual(
            [event for event, data in events],
            ["delta", "done"],
        )

        done = events[-1][1]

        self.assertEqual(done["sources"], ["sample.swift"])
        self.assertEqual(
            done["source_chunks"],
            [
                {
                    "path": "sample.swift",
                    "start_line": 10,
                    "end_line": 12,
                    "content": "let value = 1\n\nprint(value)",
                },
                {
                    "path": "sample.swift",
                    "start_line": 20,
                    "end_line": 20,
                    "content": 'let name = "DevLens"',
                },
            ],
        )