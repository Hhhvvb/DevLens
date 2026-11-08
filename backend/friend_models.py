from datetime import datetime
from uuid import UUID

from pydantic import BaseModel

class IncomingFriendRequest(BaseModel):
    id: UUID
    sender_id: UUID
    sender_nickname: str
    created_at: datetime

class FriendSummary(BaseModel):
    id: UUID
    nickname: str
    friends_since: datetime