from fastapi import Depends, HTTPException, Request
from fastapi.security import ( HTTPAuthorizationCredentials, HTTPBearer, )

from auth_models import AuthUser

bearer = HTTPBearer(auto_error=False)

def get_current_user(
    http_request: Request,
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
) -> AuthUser:
    if credentials is None:
        raise HTTPException(
            status_code=401,
            detail="请先登录。",
            headers={"WWW-Authenticate": "Bearer"},
        )

    store = http_request.app.state.session_store
    user = store.get_user(credentials.credentials)

    if user is None:
        raise HTTPException(
            status_code=401,
            detail="登录凭证无效或已过期，请重新登录。",
            headers={"WWW-Authenticate": "Bearer"}
        )

    return user