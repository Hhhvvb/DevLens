from auth_models import RegisterRequest
from email_service import LocalEmailService
from email_verification_store import EmailVerificationStore
from user_store import UserAlreadyExistsError, UserStore

class RegistrationService:
    def __init__(
        self,
        user_store: UserStore,
        verification_store: EmailVerificationStore,
        email_service: LocalEmailService,
    ):
        self.user_store = user_store
        self.verification_store = verification_store
        self.email_service = email_service

    def register(self, request: RegisterRequest) -> None:
        try:
            user = self.user_store.create(request)
        except UserAlreadyExistsError:
            user = self.user_store.get_by_email(
                str(request.email)
            )

            if user is None or user.email_verified:
                return

        token = self.verification_store.create(user.id)

        self.email_service.send_verification_email(
            email=str(user.email),
            token=token,
        )
        