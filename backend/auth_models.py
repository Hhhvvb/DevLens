from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, EmailStr, Field, SecretStr

class RegisterRequest(BaseModel):
    email: EmailStr
    password: SecretStr = Field(
        min_length=15,
        max_length=128,
    )
    nickname: str = Field(
        min_length=1,
        max_length=40,
    )

class LoginRequest(BaseModel):
    email: EmailStr
    password: SecretStr = Field(
        min_length=1,
        max_length=128,
    )

class AuthUser(BaseModel):
    id: UUID
    email: EmailStr
    nickname: str
    email_verified: bool = False

class UserRecord(AuthUser):
    password_hash: str = Field(repr=False)
    created_at: datetime

class RegisterResponse(BaseModel):
    message: str

class VerifyEmailRequest(BaseModel):
    token: SecretStr = Field(
        min_length=1,
        max_length=256,
    )

class VerifyEmailResponse(BaseModel):
    message: str

class LoginResponse(BaseModel):
    user: AuthUser
    access_token: str = Field(repr=False)
    refresh_token: str = Field(repr=False)
    expires_in: int

class RefreshRequest(BaseModel):
    refresh_token: SecretStr = Field(
        min_length=1,
        max_length=256,
    )