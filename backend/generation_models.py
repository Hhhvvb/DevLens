from enum import Enum
from uuid import UUID
from pydantic import BaseModel, Field
from repo_context import CodeChunk
from typing import Literal

class GenerationInput(BaseModel):
    question: str = Field(min_length=1, max_length=3000)

    history: list[tuple[Literal["human", "ai"], str]] = Field(default_factory=list, max_length=40,)

class GenerationState(str, Enum):
    queued = "queued"
    running = "running"
    stop_requested = "stop_requested"
    completed = "completed"
    cancelled = "cancelled"
    failed = "failed"
    interrupted = "interrupted"

class GenerationSnapshot(BaseModel):
    id: UUID
    conversation_id: UUID
    question_message_id: UUID
    answer_message_id: UUID
    state: GenerationState

    answer: str = ""
    revision: int = Field(default=0, ge=0)
    source_chunks: list[CodeChunk] = Field(default_factory=list)
    error_message: str | None = None