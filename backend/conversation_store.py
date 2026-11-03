import sqlite3
from contextlib import closing
from datetime import datetime, timezone
from pathlib import Path
from uuid import UUID

from conversation_models import ( ConversationMessage, ConversationSummary, CreateConversationRequest )

class ConversationStore:
    def __init__(self, database_path: Path):
        self.database_path = database_path

        self.database_path.parent.mkdir(
            parents=True,
            exist_ok=True,
        )

        with closing(
            sqlite3.connect(self.database_path)
        ) as connection:
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS conversations (
                    id TEXT PRIMARY KEY,
                    title TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                )
                """
            )

            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS conversation_messages (
                    id TEXT PRIMARY KEY,
                    conversation_id TEXT NOT NULL,
                    sequence INTEGER NOT NULL CHECK(sequence >= 1),
                    message_json TEXT NOT NULL,
                    UNIQUE(conversation_id, sequence)
                )
                """
            )

            connection.commit()

    def create_or_get(
        self,
        request: CreateConversationRequest,
    ) -> ConversationSummary:
        title = request.title.strip()

        if not title:
            raise ValueError("会话标题不能只包含空白字符。")

        now = datetime.now(timezone.utc).isoformat()

        with closing(
            sqlite3.connect(self.database_path)
        ) as connection:
            connection.row_factory = sqlite3.Row

            connection.execute(
                """
                INSERT INTO conversations (
                    id,
                    title,
                    created_at,
                    updated_at
                )
                VALUES (?, ?, ?, ?)
                ON CONFLICT(id) DO NOTHING
                """,
                (
                    str(request.id),
                    title,
                    now,
                    now,
                )
            )

            row = connection.execute(
                """
                SELECT id, title, created_at, updated_at
                FROM conversations
                WHERE id = ?
                """,
                (str(request.id),),
            ).fetchone()

            if row is None:
                raise RuntimeError("创建会话后未找到对应记录。")

            result = ConversationSummary.model_validate(dict(row))

            connection.commit()

            return result


    def list_conversations(self) -> list[ConversationSummary]:
        with closing(
            sqlite3.connect(self.database_path)
        ) as connection:
            connection.row_factory = sqlite3.Row

            rows = connection.execute(
                """
                SELECT id, title, created_at, updated_at
                FROM conversations
                ORDER BY updated_at DESC, id ASC
                """
            ).fetchall()

            return [
                ConversationSummary.model_validate(dict(row))
                for row in rows
            ]

    def get(
        self,
        conversation_id: UUID,
    ) -> ConversationSummary | None:
        with closing(
            sqlite3.connect(self.database_path)
        ) as connection:
            connection.row_factory = sqlite3.Row

            row = connection.execute(
                """
                SELECT id, title, created_at, updated_at
                FROM conversations
                WHERE id = ?
                """,
                (str(conversation_id),),
            ).fetchone()

            if row is None:
                return None

            return ConversationSummary.model_validate(dict(row))

    def list_messages(
        self,
        conversation_id: UUID,
    ) -> list[ConversationMessage]:
        with closing(
            sqlite3.connect(self.database_path)
        ) as connection:
            rows = connection.execute(
                """
                SELECT message_json
                FROM conversation_messages
                WHERE conversation_id = ?
                ORDER BY sequence ASC
                """,
                (str(conversation_id),),
            ).fetchall()

            return [
                ConversationMessage.model_validate_json(row[0])
                for row in rows
            ]

