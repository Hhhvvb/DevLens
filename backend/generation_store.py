import sqlite3
from contextlib import closing
from pathlib import Path
from uuid import UUID

from generation_models import ( GenerationInput, GenerationSnapshot, GenerationState, )

class GenerationConflictError(Exception):
    pass

class GenerationStore:
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
                CREATE TABLE IF NOT EXISTS generations (
                    id TEXT PRIMARY KEY,
                    conversation_id TEXT NOT NULL,
                    state TEXT NOT NULL,
                    snapshot_json TEXT NOT NULL
                )
                """
            )

            connection.execute(
                """
                CREATE UNIQUE INDEX IF NOT EXISTS
                    one_active_generation_per_conversation
                ON generations (conversation_id)
                WHERE state IN (
                    'queued',
                    'running',
                    'stop_requested'
                )
                """
            )

            connection.commit()

            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS generation_inputs (
                    generation_id TEXT PRIMARY KEY,
                    input_json TEXT NOT NULL
                )
                """
            )

    def create(
        self,
        snapshot: GenerationSnapshot,
        task_input: GenerationInput,
        ) -> None:
        with closing(
            sqlite3.connect(self.database_path)
        ) as connection:
            connection.execute(
                """
                INSERT INTO generations (
                    id,
                    conversation_id,
                    state,
                    snapshot_json
                )
                VALUES (?, ?, ?, ?)
                """,
                (
                    str(snapshot.id),
                    str(snapshot.conversation_id),
                    snapshot.state.value,
                    snapshot.model_dump_json(),
                ),
            )

            connection.execute(
                """
                INSERT INTO generation_inputs (
                    generation_id,
                    input_json
                )
                VALUES (?, ?)
                """,
                (
                    str(snapshot.id),
                    task_input.model_dump_json(),
                )
            )

            connection.commit()

    def get(self, generation_id: UUID) -> GenerationSnapshot | None:
        with closing(
            sqlite3.connect(self.database_path)
        ) as connection:
            row = connection.execute(
                """
                SELECT snapshot_json
                FROM generations
                WHERE id = ?
                """,
                (str(generation_id),),
            ).fetchone()

        if row is None:
            return None

        return GenerationSnapshot.model_validate_json(row[0])

    def get_input(
        self,
        generation_id: UUID,
    ) -> GenerationInput | None:
        with closing(
            sqlite3.connect(self.database_path)
        ) as connection:
            row = connection.execute(
                """
                SELECT input_json
                FROM generation_inputs
                WHERE generation_id = ?
                """,
                (str(generation_id),),
            ).fetchone()

        if row is None:
            return None

        return GenerationInput.model_validate_json(row[0])

    def create_or_get(
        self,
        snapshot: GenerationSnapshot,
        task_input: GenerationInput,
    ) -> GenerationSnapshot:
        try:
            self.create(snapshot, task_input)
        except sqlite3.IntegrityError as error:
            existing = self.get(snapshot.id)

            if existing is None:
                raise GenerationConflictError(
                    "当前会话已有生成任务。"
                ) from error

            existing_input = self.get_input(snapshot.id)

            if (
                existing.conversation_id != snapshot.conversation_id
                or existing_input != task_input
            ):
                raise GenerationConflictError(
                    "提交标识已被用于其他请求，请勿更改重试内容。"
                ) from error

            return existing

        return snapshot

    def claim_next(self) -> GenerationSnapshot | None:
        with closing(
            sqlite3.connect(self.database_path)
        ) as connection:
            connection.execute("BEGIN IMMEDIATE")

            row = connection.execute(
                """
                SELECT snapshot_json
                FROM generations
                WHERE state = 'queued'
                ORDER BY rowid
                LIMIT 1
                """
            ).fetchone()

            if row is None:
                return None

            snapshot = GenerationSnapshot.model_validate_json(row[0])
            snapshot.state = GenerationState.running
            snapshot.revision += 1

            connection.execute(
                """
                UPDATE generations
                SET state = ?, snapshot_json = ?
                WHERE id = ?
                """,
                (
                    snapshot.state.value,
                    snapshot.model_dump_json(),
                    str(snapshot.id),
                ),
            )

            connection.commit()

            return snapshot

    def save_progress(
        self,
        snapshot: GenerationSnapshot,
    ) -> GenerationSnapshot | None:
        if snapshot.state not in {
            GenerationState.running,
            GenerationState.completed,
            GenerationState.failed,
            GenerationState.interrupted,
        }:
            raise ValueError("不支持的生成状态。")

        with closing(
            sqlite3.connect(self.database_path)
        ) as connection:
            connection.execute("BEGIN IMMEDIATE")

            row = connection.execute(
                """
                SELECT snapshot_json
                FROM generations
                WHERE id = ?
                """,
                (str(snapshot.id),),
            ).fetchone()

            if row is None:
                return None

            current = GenerationSnapshot.model_validate_json(row[0])

            if (
                current.state != GenerationState.running
                or current.revision != snapshot.revision
            ):
                return None

            current.state = snapshot.state
            current.answer = snapshot.answer
            current.source_chunks = snapshot.source_chunks
            current.error_message = snapshot.error_message
            current.revision += 1

            connection.execute(
                """
                UPDATE generations
                SET state = ?, snapshot_json = ?
                WHERE id = ?
                """,
                (
                    current.state.value,
                    current.model_dump_json(),
                    str(current.id),
                ),
            )

            connection.commit()

            return current

    def recover_unfinished(self) -> int:
        with closing(
            sqlite3.connect(self.database_path)
        ) as connection:
            connection.execute("BEGIN IMMEDIATE")

            rows = connection.execute(
                """
                SELECT snapshot_json
                FROM generations
                WHERE state IN ('running', 'stop_requested')
                """
            ).fetchall()

            for row in rows:
                snapshot = GenerationSnapshot.model_validate_json(
                    row[0]
                )

                if snapshot.state == GenerationState.stop_requested:
                    snapshot.state = GenerationState.cancelled
                    snapshot.error_message = None
                else:
                    snapshot.state = GenerationState.interrupted
                    snapshot.error_message = (
                        "后台执行器意外退出，回答已中断，请重新提问。"
                    )

                snapshot.revision += 1

                connection.execute(
                    """
                    UPDATE generations
                    SET state = ?, snapshot_json = ?
                    WHERE id = ?
                    """,
                    (
                        snapshot.state.value,
                        snapshot.model_dump_json(),
                        str(snapshot.id),
                    ),
                )


            connection.commit()

            return len(rows)

    def request_stop(
        self,
        generation_id: UUID,
    ) -> GenerationSnapshot | None:
        with closing(
            sqlite3.connect(self.database_path)
        ) as connection:
            connection.execute("BEGIN IMMEDIATE")

            row = connection.execute(
                """
                SELECT snapshot_json
                FROM generations
                WHERE id = ?
                """,
                (str(generation_id),),
            ).fetchone()

            if row is None:
                return None

            snapshot = GenerationSnapshot.model_validate_json(row[0])

            if snapshot.state == GenerationState.queued:
                snapshot.state = GenerationState.cancelled
            elif snapshot.state == GenerationState.running:
                snapshot.state = GenerationState.stop_requested
            else:
                return snapshot

            snapshot.error_message = None
            snapshot.revision += 1

            connection.execute(
                """
                UPDATE generations
                SET state = ?, snapshot_json = ?
                WHERE id = ?
                """,
                (
                    snapshot.state.value,
                    snapshot.model_dump_json(),
                    str(snapshot.id),
                ),
            )

            connection.commit()

            return snapshot

    def finish_stop(
        self,
        snapshot: GenerationSnapshot,
    ) -> GenerationSnapshot | None:
        with closing(
            sqlite3.connect(self.database_path)
        ) as connection:
            connection.execute("BEGIN IMMEDIATE")

            row = connection.execute(
                """
                SELECT snapshot_json
                FROM generations
                WHERE id = ?
                """,
                (str(snapshot.id),),
            ).fetchone()

            if row is None:
                return None

            current = GenerationSnapshot.model_validate_json(row[0])

            if current.state != GenerationState.stop_requested:
                return None

            if snapshot.answer.startswith(current.answer):
                current.answer = snapshot.answer

            if snapshot.source_chunks:
                current.source_chunks = snapshot.source_chunks

            current.state = GenerationState.cancelled
            current.error_message = None
            current.revision += 1

            connection.execute(
                """
                UPDATE generations
                SET state = ?, snapshot_json = ?
                WHERE id = ?
                """,
                (
                    current.state.value,
                    current.model_dump_json(),
                    str(current.id),
                ),
            )

            connection.commit()

            return current
