import sqlite3
import hashlib
import time

from contextlib import closing
from pathlib import Path
from secrets import token_urlsafe
from uuid import uuid4

from auth_models import AuthUser, LoginResponse

class SessionStore:
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
                CREATE TABLE IF NOT EXISTS auth_sessions (
                    id TEXT PRIMARY KEY,
                    user_id TEXT NOT NULL,
                    created_at INTEGER NOT NULL,
                    expires_at INTEGER NOT NULL,
                    revoked_at INTEGER
                )
                """
            )

            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS auth_tokens (
                    token_hash TEXT PRIMARY KEY,
                    session_id TEXT NOT NULL,
                    kind TEXT NOT NULL
                        CHECK (kind IN ('access', 'refresh')),
                    expires_at INTEGER NOT NULL,
                    used_at INTEGER
                )
                """
            )

            connection.commit()

    def create(self, user: AuthUser) -> LoginResponse:
        session_id = str(uuid4())
        now = int(time.time())

        access_lifetime = 15 * 60
        refresh_lifetime = 30 * 24 * 60 * 60

        access_token = token_urlsafe(32)
        refresh_token = token_urlsafe(32)

        with closing(
            sqlite3.connect(self.database_path)
        ) as connection:
            connection.execute("BEGIN IMMEDIATE")

            connection.execute(
                """
                INSERT INTO auth_sessions (
                    id,
                    user_id,
                    created_at,
                    expires_at
                )
                VALUES (?, ?, ?, ?)
                """,
                (
                    session_id,
                    str(user.id),
                    now,
                    now + refresh_lifetime,
                )
            )

            tokens = [
                (
                    access_token,
                    "access",
                    now + access_lifetime,
                ),
                (
                    refresh_token,
                    "refresh",
                    now + refresh_lifetime,
                )
            ]

            for token, kind, expires_at in tokens:
                connection.execute(
                    """
                    INSERT INTO auth_tokens (
                        token_hash,
                        session_id,
                        kind,
                        expires_at
                    )
                    VALUES (?, ?, ?, ?)
                    """,
                    (
                        self._hash_token(token),
                        session_id,
                        kind,
                        expires_at,
                    )
                )

            connection.commit()

        return LoginResponse(
            user=user,
            access_token=access_token,
            refresh_token=refresh_token,
            expires_in=access_lifetime,
        )

    def get_user(self, access_token: str) -> AuthUser | None:
        token_hash = self._hash_token(access_token)
        now = int(time.time())

        with closing(
            sqlite3.connect(self.database_path)
        ) as connection:
            connection.row_factory = sqlite3.Row

            row = connection.execute(
                """
                SELECT
                    u.id,
                    u.email,
                    u.nickname,
                    u.email_verified
                FROM auth_tokens AS t
                JOIN auth_sessions AS s ON s.id = t.session_id
                JOIN users AS u ON u.id = s.user_id
                WHERE t.token_hash = ?
                  AND t.kind = 'access'
                  AND t.expires_at > ?
                  AND s.expires_at > ?
                  AND s.revoked_at IS NULL
                  AND u.email_verified = 1
                """,
                (token_hash, now, now),
            ).fetchone()

            if row is None:
                return None

            return AuthUser.model_validate(dict(row))

    @staticmethod
    def _hash_token(token: str) -> str:
        return hashlib.sha256(
            token.encode("utf-8")
        ).hexdigest()