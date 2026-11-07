from secrets import token_urlsafe

from auth_models import AuthUser, LoginRequest
from password_service import hash_password, verify_password
from user_store import UserStore

class InvalidCredentialsError(Exception):
    pass

class EmailNotVerifiedError(Exception):
    pass

class AuthenticationService:
    def __init__(self, user_store: UserStore):
        self.user_store = user_store
        self._dummy_hash = hash_password(
            token_urlsafe(32)
        )

    def authenticate(
        self,
        request: LoginRequest,
    ) -> AuthUser:
        user = self.user_store.get_by_email(
            str(request.email)
        )

        store_hash = (
            user.password_hash
            if user is not None
            else self._dummy_hash
        )

        password_matches = verify_password(
            request.password.get_secret_value(),
            store_hash,
        )

        if user is None or not password_matches:
            raise InvalidCredentialsError(
                "邮箱或密码不正确。"
            )

        if not user.email_verified:
            raise EmailNotVerifiedError(
                "请先验证邮箱后再登录。"
            )

        return AuthUser(
            id=user.id,
            email=user.email,
            nickname=user.nickname,
            email_verified=user.email_verified,
        )
    