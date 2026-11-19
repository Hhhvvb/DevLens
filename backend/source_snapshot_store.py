import sqlite3
from contextlib import closing
from dataclasses import dataclass
from pathlib import Path
from uuid import UUID

@dataclass(frozen=True)
class SourceSnapshot:
    id: UUID
    owner_id: UUID
    name: str
    collection_name: str

class SourceSnapshotStore:
    def __init__(self, database_path: Path):
        self.database_path = database_path
        database_path.parent.mkdir(parents=True, exist_ok=True)

        with closing(sqlite3.connect(database_path)) as connection:
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS source_snapshots (
                    id TEXT PRIMARY KEY,
                    owner_id TEXT NOT NULL,
                    name TEXT NOT NULL,
                    collection_name TEXT NOT NULL UNIQUE
                )
                """
            )
            connection.commit()

    def register_ready(self, snapshot: SourceSnapshot) -> None:
        with closing(sqlite3.connect(self.database_path)) as connection:
            connection.execute(
                """
                INSERT INTO source_snapshots (id, owner_id, name, collection_name)
                VALUES (?, ?, ?, ?)
                """,
                (
                    str(snapshot.id),
                    str(snapshot.owner_id),
                    snapshot.name,
                    snapshot.collection_name,
                ),
            )
            connection.commit()

    def get_for_owner(
        self,
        snapshot_id: UUID,
        owner_id: UUID,
    ) -> SourceSnapshot | None:
        with closing(sqlite3.connect(self.database_path)) as connection:
            row = connection.execute(
                """
                SELECT id, owner_id, name, collection_name
                FROM source_snapshots
                WHERE id = ? AND owner_id = ?
                """,
                (str(snapshot_id), str(owner_id)),
            ).fetchone()

        if row is None:
            return None

        return SourceSnapshot(
            id=UUID(row[0]),
            owner_id=UUID(row[1]),
            name=row[2],
            collection_name=row[3],
        )