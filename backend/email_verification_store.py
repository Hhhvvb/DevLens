import hashlib
import sqlite3
import time

from contextlib import closing
from pathlib import Path
from secrets import token_urlsafe
from uuid import UUID

class EmailVerificationStore:
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
                CREATE TABLE IF NOT EXISTS email_verification_tokens (
                    token_hash TEXT PRIMARY KEY,
                    user_id TEXT NOT NULL,
                    expires_at INTEGER NOT NULL,
                    used_at INTEGER
                )
                """
            )

            connection.commit()

    def create(self, user_id: UUID) -> str:
        token = token_urlsafe(32)
        token_hash = self._hash_token(token)
        expires_at = int(time.time()) + 30 * 60

        with closing(
            sqlite3.connect(self.database_path)
        ) as connection:
            row  = connection.execute(
                """
                SELECT email_verified
                FROM users
                WHERE id = ?
                """,
                (str(user_id),),
            ).fetchone()

            if row is None:
                raise ValueError("账号不存在。")

            if row[0]:
                raise ValueError("邮箱已经验证。")

            connection.execute(
                """
                INSERT INTO email_verification_tokens (
                    token_hash,
                    user_id,
                    expires_at
                )
                VALUES (?, ?, ?)
                """,
                (
                    token_hash,
                    str(user_id),
                    expires_at,
                )
            )

            connection.commit()

        return token

    def consume(self, token: str) -> bool:
        token_hash = self._hash_token(token)
        now = int(time.time())

        with closing(
            sqlite3.connect(self.database_path)
        ) as connection:
            connection.execute("BEGIN IMMEDIATE")

            row = connection.execute(
                """
                SELECT t.user_id
                FROM email_verification_tokens AS t
                JOIN users AS u ON u.id = t.user_id
                WHERE t.token_hash = ?
                  AND t.used_at IS NULL
                  AND t.expires_at > ?
                  AND u.email_verified = 0
                """,
                (token_hash, now),
            ).fetchone()

            if row is None:
                return False

            user_id = row[0]

            connection.execute(
                """
                UPDATE users
                SET email_verified = 1
                WHERE id = ?
                """,
                (user_id,),
            )

            connection.execute(
                """
                UPDATE email_verification_tokens
                SET used_at = ?
                WHERE user_id = ?
                  AND used_at IS NULL
                """,
                (now, user_id),
            )

            connection.commit()

            return True

    @staticmethod
    def _hash_token(token: str) -> str:
        return hashlib.sha256(
            token.encode("utf-8")
        ).hexdigest()