import sqlite3
from contextlib import closing
from datetime import datetime, timezone
from pathlib import Path
from uuid import uuid4

from auth_models import AuthUser, RegisterRequest, UserRecord
from password_service import hash_password

class UserAlreadyExistsError(Exception):
    pass

def email_lookup_key(email: str) -> str:
    return email.strip().casefold()

class UserStore:
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
                CREATE TABLE IF NOT EXISTS users (
                    id TEXT PRIMARY KEY,
                    email TEXT NOT NULL,
                    email_key TEXT NOT NULL UNIQUE,
                    nickname TEXT NOT NULL,
                    password_hash TEXT NOT NULL,
                    email_verified INTEGER NOT NULL DEFAULT 0,
                    created_at TEXT NOT NULL
                )
                """
            )

            connection.commit()

    def create(
        self,
        request: RegisterRequest,
    ) -> AuthUser:
        email = str(request.email)
        nickname = request.nickname.strip()

        if not nickname:
            raise ValueError("昵称不能为空或只包含空白字符。")

        user_id = uuid4()
        now = datetime.now(timezone.utc)

        password_hash = hash_password(
            request.password.get_secret_value()
        )

        with closing(
            sqlite3.connect(self.database_path)
        ) as connection:
            cursor = connection.execute(
                """
                INSERT INTO users (
                    id,
                    email,
                    email_key,
                    nickname,
                    password_hash,
                    email_verified,
                    created_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(email_key) DO NOTHING
                """,
                (
                    str(user_id),
                    email,
                    email_lookup_key(email),
                    nickname,
                    password_hash,
                    0,
                    now.isoformat(),
                ),
            )

            if cursor.rowcount == 0:
                raise UserAlreadyExistsError(
                    "该邮箱已有账号记录。"
                )

            connection.commit()

        return AuthUser(
            id=user_id,
            email=email,
            nickname=nickname,
            email_verified=False,
        )

    def get_by_email(
        self,
        email: str,
    ) -> UserRecord | None:
        with closing(
            sqlite3.connect(self.database_path)
        ) as connection:
            connection.row_factory = sqlite3.Row

            row = connection.execute(
                """
                SELECT
                    id,
                    email,
                    nickname,
                    password_hash,
                    email_verified,
                    created_at
                FROM users
                WHERE email_key = ?
                """,
                (email_lookup_key(email),),
            ).fetchone()

            if row is None:
                return None

            return UserRecord.model_validate(dict(row))