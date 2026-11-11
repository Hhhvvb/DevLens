import sqlite3
from contextlib import closing
from datetime import datetime, timezone, timedelta
from pathlib import Path
from uuid import UUID, uuid4

from conversation_models import ( IncomingConversationInvitation, ConversationMessage, ConversationSummary, CreateConversationRequest )

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

            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS conversation_invitations (
                    id TEXT PRIMARY KEY,
                    conversation_id TEXT NOT NULL,
                    inviter_id TEXT NOT NULL,
                    recipient_id TEXT NOT NULL,
                    status TEXT NOT NULL DEFAULT 'pending'
                        CHECK (status IN (
                            'pending', 'accepted', 'declined',
                            'revoked', 'expired'
                        )),
                    created_at TEXT NOT NULL,
                    expires_at TEXT NOT NULL,
                    responded_at TEXT,
                    CHECK (inviter_id <> recipient_id)
                )
                """
            )

            connection.execute(
                """
                CREATE UNIQUE INDEX IF NOT EXISTS
                    one_pending_invitation_per_recipient
                ON conversation_invitations (
                    conversation_id,
                    recipient_id
                )
                WHERE status = 'pending'
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

    def invite_friend(
        self,
        conversation_id: UUID,
        inviter_id: UUID,
        recipient_id: UUID,
    ) -> None:
        conversation = str(conversation_id)
        inviter = str(inviter_id)
        recipient = str(recipient_id)

        with closing(sqlite3.connect(self.database_path)) as connection:
            connection.execute("BEGIN IMMEDIATE")

            owner = connection.execute(
                """
                SELECT 1
                FROM conversation_members
                WHERE conversation_id = ?
                  AND user_id = ?
                  AND role = 'owner'
                """,
                (conversation, inviter)
            )

            if owner is None:
                raise PermissionError("会话不存在或无权邀请。")

            if inviter == recipient:
                raise ValueError("不能邀请自己。")


            first_user_id, second_user_id = sorted((inviter, recipient))

            friendship = connection.execute(
                """
                SELECT 1
                FROM friendships
                WHERE first_user_id = ?
                  AND second_user_id = ?
                """,
                (first_user_id, second_user_id),
            ).fetchone()

            if friendship is None:
                raise ValueError("只能邀请好友加入会话。")

            member = connection.execute(
                """
                SELECT 1
                FROM conversation_members
                WHERE conversation_id = ?
                  AND user_id = ?
                """,
            ).fetchone()

            if member is not None:
                raise ValueError("该用户已是会话成员。")

            now = datetime.now(timezone.utc)
            created_at = now.isoformat()
            expires_at = (now + timedelta(days=7)).isoformat()

            connection.execute(
                """
                UPDATE conversation_invitations
                SET status = 'expired'
                WHERE conversation_id = ?
                  AND recipient_id = ?
                  AND status = 'pending'
                  AND expires_at <= ?
                """,
                (conversation, recipient, created_at)
            )

            connection.execute(
                """
                INSERT INTO conversation_invitations (
                    id, conversation_id, inviter_id, recipient_id,
                    status, created_at, expires_at
                )
                VALUES (?, ?, ?, ?, 'pending', ?, ?)
                ON CONFLICT(conversation_id, recipient_id)
                    WHERE status = 'pending'
                DO NOTHING
                """,
                (
                    str(uuid4()),
                    conversation,
                    inviter,
                    recipient,
                    created_at,
                    expires_at,
                ),
            )

            connection.commit()

    def list_incoming_invitations(
        self,
        recipient_id: UUID,
    ) -> list[IncomingConversationInvitation]:
        now = datetime.now(timezone.utc).isoformat()

        with closing(sqlite3.connect(self.database_path)) as connection:
            connection.row_factory = sqlite3.Row

            rows = connection.execute(
                """
                SELECT
                    i.id,
                    c.title AS conversation_title,
                    u.nickname AS inviter_nickname,
                    i.created_at,
                    i.expires_at
                FROM conversation_invitations AS i
                JOIN conversations AS c ON c.id = i.conversation_id
                JOIN users AS u ON u.id = i.inviter_id
                WHERE i.recipient_id = ?
                  AND i.status = 'pending'
                  AND i.expires_at > ?
                ORDER BY i.created_at DESC, i.id ASC
                """,
                (str(recipient_id), now),
            ).fetchall()

            return [
                IncomingConversationInvitation.model_validate(dict(row))
                for row in rows
            ]

    def accept_invitation(
        self,
        invitation_id: UUID,
        recipient_id: UUID,
    ) -> UUID | None:
        recipient = str(recipient_id)

        with closing(sqlite3.connect(self.database_path)) as connection:
            connection.row_factory = sqlite3.Row
            connection.execute("BEGIN IMMEDIATE")

            invitation = connection.execute(
                """
                SELECT i.conversation_id, i.inviter_id, i.status, i.expires_at
                FROM conversation_invitations AS i
                JOIN conversations AS c ON c.id = i.conversation_id
                WHERE i.id = ? AND i.recipient_id = ?
                """,
                (str(invitation_id), recipient),
            ).fetchone()

            if invitation is None:
                return None

            conversation = invitation["conversation_id"]
            conversation_id = UUID(conversation)

            if invitation["status"] == "accepted":
                member = connection.execute(
                    """
                    SELECT 1
                    FROM conversation_members
                    WHERE conversation_id = ? AND user_id = ?
                    """,
                    (conversation, recipient)
                ).fetchone()

                return conversation_id if member is not None else None

            now = datetime.now(timezone.utc).isoformat()

            if invitation["status"] != "pending" or invitation["expires_at"] <= now:
                return None

            inviter = invitation["inviter_id"]

            owner = connection.execute(
                """
                SELECT 1
                FROM conversation_members
                WHERE conversation_id = ?
                  AND user_id = ?
                  AND role = 'owner'
                """,
                (conversation, inviter),
            ).fetchone()

            first_user_id, second_user_id = sorted((inviter, recipient))
            friendship = connection.execute(
                """
                SELECT 1
                FROM friendships
                WHERE first_user_id = ? AND second_user_id = ?
                """,
                (first_user_id, second_user_id),
            ).fetchone()

            if owner is None or friendship is None:
                return None

            connection.execute(
                """
                INSERT INTO conversation_members (
                    conversation_id, user_id, role, joined_at
                )
                VALUES (?, ?, 'member', ?)
                ON CONFLICT(conversation_id, user_id) DO NOTHING
                """,
                (conversation, recipient, now),
            )

            connection.execute(
                """
                UPDATE conversation_invitations
                SET status = 'accepted', responded_at = ?
                WHERE id = ?
                """,
                (now, str(invitation_id)),
            )

            connection.commit()
            return conversation_id

    def decline_invitation(
        self,
        invitation_id: UUID,
        recipient_id: UUID,
    ) -> bool:
        now = datetime.now(timezone.utc).isoformat()

        with closing(sqlite3.connect(self.database_path)) as connection:
            cursor = connection.execute(
                """
                UPDATE conversation_invitations
                SET
                    status = 'declined',
                    responded_at = COALESCE(responded_at, ?)
                WHERE id = ?
                AND recipient_id = ?
                AND (
                    (status = 'pending' AND expires_at > ?)
                    OR status = 'declined'
                )
                """,
                (
                    now,
                    str(invitation_id),
                    str(recipient_id),
                    now,
                ),
            )

            connection.commit()
            return cursor.rowcount == 1