from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field
from typing import Literal

from repo_context import CodeChunk

class CreateConversationRequest(BaseModel):
    id: UUID
    title: str = Field(
        default="新会话",
        min_length=1,
        max_length=80,
    )

class ConversationSummary(BaseModel):
    id: UUID
    title: str
    created_at: datetime
    updated_at: datetime
    member_count: int = Field(ge=1)

class ConversationMessage(BaseModel):
    id: UUID
    conversation_id: UUID
    sequence: int = Field(ge=1)
    role: Literal["user", "assistant"]

    text: str = ""
    source_chunks: list[CodeChunk] = Field(
        default_factory=list,
    )
    status_text: str | None = None
    is_excluded_from_context: bool = False

    created_at: datetime

class CreateConversationInvitationRequest(BaseModel):
    recipient_id: UUID

class IncomingConversationInvitation(BaseModel):
    id: UUID
    conversation_title: str
    inviter_nickname: str
    created_at: datetime
    expires_at: datetime