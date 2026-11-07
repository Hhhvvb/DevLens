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

            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS conversation_members (
                    conversation_id TEXT NOT NULL,
                    user_id TEXT NOT NULL,
                    role TEXT NOT NULL
                        CHECK (role IN ('owner', 'admin', 'member')),
                    joined_at TEXT NOT NULL,
                    PRIMARY KEY (conversation_id, user_id)
                )
                """
            )

            connection.execute(
                """
                CREATE INDEX IF NOT EXISTS
                    conversation_members_by_user
                ON conversation_members (user_id)
                """
            )

            connection.execute(
                """
                CREATE UNIQUE INDEX IF NOT EXISTS
                    one_owner_per_conversation
                ON conversation_members (conversation_id)
                WHERE role = 'owner'
                """
            )

            connection.commit()

    def create_or_get(
        self,
        request: CreateConversationRequest,
        user_id: UUID,
    ) -> ConversationSummary:
        title = request.title.strip()

        if not title:
            raise ValueError("会话标题不能只包含空白字符。")

        now = datetime.now(timezone.utc).isoformat()

        with closing(
            sqlite3.connect(self.database_path)
        ) as connection:
            connection.row_factory = sqlite3.Row
            connection.execute("BEGIN IMMEDIATE")

            row = connection.execute(
                """
                SELECT id, title, created_at, updated_at
                FROM conversations
                WHERE id = ?
                """,
                (str(request.id),),
            ).fetchone()

            if row is not None:
                membership = connection.execute(
                    """
                    SELECT role
                    FROM conversation_members
                    WHERE conversation_id = ?
                      AND user_id = ?
                    """,
                    (str(request.id), str(user_id)),
                ).fetchone()

                if membership is None:
                    raise PermissionError("会话不存在或无权访问。")

                return ConversationSummary.model_validate(dict(row))

            connection.execute(
                """
                INSERT INTO conversations (
                    id,
                    title,
                    created_at,
                    updated_at
                )
                VALUES (?, ?, ?, ?)
                """,
                (
                    str(request.id),
                    title,
                    now,
                    now,
                )
            )

            connection.execute(
                """
                INSERT INTO conversation_members (
                    conversation_id,
                    user_id,
                    role,
                    joined_at
                )
                VALUES (?, ?, 'owner', ?)
                """,
                (
                    str(request.id),
                    str(user_id),
                    now,
                ),
            )

            result = ConversationSummary(
                id=request.id,
                title=title,
                created_at=now,
                updated_at=now,
            )

            connection.commit()

            return result


    def list_conversations(
        self,
        user_id: UUID,
    ) -> list[ConversationSummary]:
        with closing(
            sqlite3.connect(self.database_path)
        ) as connection:
            connection.row_factory = sqlite3.Row

            rows = connection.execute(
                """
                SELECT c.id, c.title, c.created_at, c.updated_at
                FROM conversation_members AS m
                JOIN conversations AS c ON c.id = m.conversation_id
                WHERE m.user_id = ?
                ORDER BY c.updated_at DESC, c.id ASC
                """,
                (str(user_id),),
            ).fetchall()

            return [
                ConversationSummary.model_validate(dict(row))
                for row in rows
            ]

    def get(
        self,
        conversation_id: UUID,
        user_id: UUID,
    ) -> ConversationSummary | None:
        with closing(
            sqlite3.connect(self.database_path)
        ) as connection:
            connection.row_factory = sqlite3.Row

            row = connection.execute(
                """
                SELECT c.id, c.title, c.created_at, c.updated_at
                FROM conversations AS c
                JOIN conversation_members AS m
                    ON m.conversation_id = c.id
                WHERE c.id = ?
                  AND m.user_id = ?
                """,
                (str(conversation_id), str(user_id)),
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

