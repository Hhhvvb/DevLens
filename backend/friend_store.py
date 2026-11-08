import sqlite3
from contextlib import closing
from pathlib import Path
from datetime import datetime, timezone
from uuid import UUID, uuid4
from friend_models import FriendSummary, IncomingFriendRequest

class FriendStore:
    def __init__(self, database_path: Path):
        self.database_path = database_path

        with closing(sqlite3.connect(self.database_path)) as connection:
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS friend_requests (
                    id TEXT PRIMARY KEY,
                    sender_id TEXT NOT NULL,
                    recipient_id TEXT NOT NULL,
                    status TEXT NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending', 'accepted', 'declined')),
                    created_at TEXT NOT NULL,
                    responded_at TEXT,
                    CHECK (sender_id <> recipient_id)
                )
                """
            )

            connection.execute(
                """
                CREATE UNIQUE INDEX IF NOT EXISTS
                    one_pending_friend_request_per_pair
                ON friend_requests (
                    min(sender_id, recipient_id),
                    max(sender_id, recipient_id)
                )
                WHERE status = 'pending'
                """
            )

            connection.execute(
                 """
                CREATE TABLE IF NOT EXISTS friendships (
                    first_user_id TEXT NOT NULL,
                    second_user_id TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    PRIMARY KEY (first_user_id, second_user_id),
                    CHECK (first_user_id < second_user_id)
                )
                """
            )

            connection.commit()

    def send_request(self, sender_id: UUID, recipient_id: UUID) -> None:
        sender = str(sender_id)
        recipient = str(recipient_id)

        if sender == recipient:
            raise ValueError("不能向自己发送好友请求。")

        first_user_id, second_user_id = sorted((sender, recipient))
        now = datetime.now(timezone.utc).isoformat()

        with closing(sqlite3.connect(self.database_path)) as connection:
            connection.execute("BEGIN IMMEDIATE")

            friendship = connection.execute(
                """
                SELECT 1
                FROM friendships
                WHERE first_user_id = ?
                  AND second_user_id = ?
                """,
                (first_user_id, second_user_id),
            ).fetchone()

            if friendship is not None:
                return

            connection.execute(
                """
                INSERT INTO friend_requests (
                    id, sender_id, recipient_id, status, created_at
                )
                VALUES (?, ?, ?, 'pending', ?)
                ON CONFLICT DO NOTHING
                """,
                (str(uuid4()), sender, recipient, now),
            )

            connection.commit()

    def list_incoming_requests(
        self,
        recipient_id: UUID,
    ) -> list[IncomingFriendRequest]:
        with closing(sqlite3.connect(self.database_path)) as connection:
            connection.row_factory = sqlite3.Row

            rows = connection.execute(
                """
                SELECT
                    r.id,
                    r.sender_id,
                    u.nickname AS sender_nickname,
                    r.created_at
                FROM friend_requests AS r
                JOIN users AS u ON u.id = r.sender_id
                WHERE r.recipient_id = ?
                  AND r.status = 'pending'
                ORDER BY r.created_at DESC, r.id ASC
                """,
                (str(recipient_id),),
            ).fetchall()

            return [
                IncomingFriendRequest.model_validate(dict(row))
                for row in rows
            ]

    def accept_request(
        self,
        request_id: UUID,
        recipient_id: UUID,
    ) -> bool:
        with closing(sqlite3.connect(self.database_path)) as connection:
            connection.row_factory = sqlite3.Row
            connection.execute("BEGIN IMMEDIATE")

            row = connection.execute(
                """
                SELECT sender_id, recipient_id, status
                FROM friend_requests
                WHERE id = ?
                  AND recipient_id = ?
                  AND status IN ('pending', 'accepted')
                """,
                (str(request_id), str(recipient_id)),
            ).fetchone()

            if row is None:
                return False

            if row["status"] == "accepted":
                return True

            first_user_id, second_user_id = sorted((row["sender_id"], row["recipient_id"]))
            now = datetime.now(timezone.utc).isoformat()

            connection.execute(
                """
                INSERT INTO friendships (
                    first_user_id, second_user_id, created_at
                )
                VALUES (?, ?, ?)
                ON CONFLICT(first_user_id, second_user_id) DO NOTHING
                """,
                (first_user_id, second_user_id, now),
            )

            connection.execute(
                """
                UPDATE friend_requests
                SET status = 'accepted', responded_at = ?
                WHERE id = ?
                """,
                (now, str(request_id)),
            )

            connection.commit()
            return True

    def list_friends(self, user_id: UUID) -> list[FriendSummary]:
        current_user_id = str(user_id)

        with closing(sqlite3.connect(self.database_path)) as connection:
            connection.row_factory = sqlite3.Row

            rows = connection.execute(
                """
                SELECT
                    u.id,
                    u.nickname,
                    f.created_at AS friends_since
                FROM friendships AS f
                JOIN users AS u ON u.id = CASE
                    WHEN f.first_user_id = ? THEN f.second_user_id
                    ELSE f.first_user_id
                END
                WHERE f.first_user_id = ?
                   OR f.second_user_id = ?
                ORDER BY f.created_at DESC, u.id ASC
                """,
                (current_user_id, current_user_id, current_user_id),
            ).fetchall()

            return [
                FriendSummary.model_validate(dict(row))
                for row in rows
            ]