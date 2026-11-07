import os
import json
import asyncio

from openai import APIError, APITimeoutError
from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field
from llm_service import ( ask_question, stream_question, StreamAnswerError )
from dataclasses import asdict
from contextlib import asynccontextmanager
from starlette.concurrency import run_in_threadpool
from code_retriever import CodeRetriever
from repo_context import CodeChunk
from typing import Literal
from retrieval_service import search_with_history
from pathlib import Path
from uuid import UUID, uuid4
from generation_models import ( GenerationInput, GenerationSnapshot, GenerationState, )
from generation_store import ( GenerationConflictError, GenerationStore, )
from conversation_models import ( CreateConversationRequest, ConversationSummary, ConversationMessage, )
from conversation_store import ConversationStore
from user_store import UserStore
from auth_service import ( AuthenticationService, EmailNotVerifiedError, InvalidCredentialsError, )
from auth_models import ( RefreshRequest, AuthUser, LoginRequest, LoginResponse, RegisterRequest, RegisterResponse, VerifyEmailRequest, VerifyEmailResponse,)
from email_service import LocalEmailService
from email_verification_store import EmailVerificationStore
from registration_service import RegistrationService
from smtplib import SMTPException
from session_store import SessionStore
from auth_dependencies import get_current_user

@asynccontextmanager
async def lifespan(app: FastAPI):
    database_path = (
        Path(__file__).resolve().parent
        / ".data"
        / "generations.sqlite3"
    )

    app.state.generation_store = await run_in_threadpool(
        GenerationStore,
        database_path,
    )

    app.state.conversation_store = await run_in_threadpool(
        ConversationStore,
        database_path,
    )

    app.state.user_store = await run_in_threadpool(
        UserStore,
        database_path,
    )

    app.state.session_store = await run_in_threadpool(
        SessionStore,
        database_path,
    )

    app.state.email_verification_store = await run_in_threadpool(
        EmailVerificationStore,
        database_path,
    )

    app.state.registration_service = RegistrationService(
        user_store=app.state.user_store,
        verification_store=app.state.email_verification_store,
        email_service=LocalEmailService(),
    )

    app.state.auth_service = await run_in_threadpool(
        AuthenticationService,
        app.state.user_store,
    )

    app.state.retriever = await run_in_threadpool(
        CodeRetriever
    )

    app.state.retrieval_lock = asyncio.Lock()

    try:
        yield
    finally:
        del app.state.retriever
        del app.state.generation_store
        del app.state.conversation_store
        del app.state.auth_service
        del app.state.user_store
        del app.state.registration_service
        del app.state.email_verification_store
        del app.state.session_store

app = FastAPI(
    title="DevLens",
    lifespan=lifespan,
)

class EchoRequest(BaseModel):
    question: str = Field(min_length=1, max_length=3000)

class HistoryMessage(BaseModel):
    role: Literal["user", "assistant"]
    content: str = Field(min_length=1, max_length=16000)

class AskRequest(BaseModel):
    question: str = Field(min_length=1, max_length=3000)
    history: list[HistoryMessage] = Field(
        default_factory=list,
        max_length=40,
    )

class CreateGenerationRequest(AskRequest):
    conversation_id: UUID
    request_id: UUID

class ConversationGenerationRecovery(BaseModel):
    snapshot: GenerationSnapshot
    request: CreateGenerationRequest

class AskResponse(BaseModel):
    question: str
    answer: str

def prepare_history(
    request: AskRequest,
) -> list[tuple[str, str]]:
    total_length = 0
    history: list[tuple[str, str]] = []

    for message in request.history:
        total_length += len(message.content)

        if total_length > 24000:
            raise HTTPException(
                status_code=422,
                detail="当前会话历史过长，请新建会话后继续。",
            )

        if message.role == "user":
            role = "human"
        else:
            role = "ai"

        history.append((role, message.content))

    return history

def encode_sse(event: str, data: dict[str, object]) -> str:
    payload = json.dumps(data, ensure_ascii=False)
    return f"event: {event}\ndata:{payload}\n\n"

async def retrieve_chunks(
    http_request: Request,
    question: str,
    history: list[tuple[str, str]],
) -> list[CodeChunk]:
    try:
        async with http_request.app.state.retrieval_lock:
            return await run_in_threadpool(
                search_with_history,
                http_request.app.state.retriever,
                question,
                history,
            )
    except ValueError as error:
        raise HTTPException(
            status_code=422,
            detail=str(error),
        ) from error
    except RuntimeError as error:
        raise HTTPException(
            status_code=503,
            detail="代码检索暂不可用，请检查索引或服务日志。",
        ) from error

@app.get("/health")
def health():
    return {
        "status": "ok",
        "service": "DevLens",
        "version": "0.1.0"
    }

@app.post(
    "/v1/auth/register",
    response_model=RegisterResponse,
    status_code=202,
)
def register(
    request: RegisterRequest,
    http_request: Request,
) -> RegisterResponse:
    service = http_request.app.state.registration_service

    try:
        service.register(request)
    except ValueError as error:
        raise HTTPException(
            status_code=422,
            detail=str(error),
        ) from error
    except (SMTPException, OSError) as error:
        raise HTTPException(
            status_code=503,
            detail="验证邮件暂时发送失败，请稍后重新提交注册。"
        ) from error

    return RegisterResponse(
        message=(
            "如果该邮箱可以注册或尚未完成验证，"
            "验证邮件将发送至该邮箱，请查收。"
        )
    )

@app.post(
    "/v1/auth/verify-email",
    response_model=VerifyEmailResponse,
    status_code=200,
)
def verify_email(
    request: VerifyEmailRequest,
    http_request: Request,
) -> VerifyEmailResponse:
    store = http_request.app.state.email_verification_store

    verified = store.consume(
        request.token.get_secret_value()
    )

    if not verified:
        raise HTTPException(
            status_code=400,
            detail="验证信息无效、已过期或已使用，请重新申请验证邮件。",
        )

    return VerifyEmailResponse(
        message="邮箱验证成功。",
    )

@app.post(
    "/v1/auth/login",
    response_model=LoginResponse,
    status_code=200,
)
def login(
    request: LoginRequest,
    http_request: Request,
) -> LoginResponse:
    auth_service = http_request.app.state.auth_service
    session_store = http_request.app.state.session_store

    try:
        user = auth_service.authenticate(request)
    except InvalidCredentialsError as error:
        raise HTTPException(
            status_code=401,
            detail="邮箱或密码不正确。",
        ) from error
    except EmailNotVerifiedError as error:
        raise HTTPException(
            status_code=403,
            detail="请先验证邮箱后再登录。",
        ) from error

    response = session_store.create(user)

    return response

@app.post(
    "/v1/auth/refresh",
    response_model=LoginResponse,
    status_code=200,
)
def refresh_session(
    request: RefreshRequest,
    http_request: Request,
) -> LoginResponse:
    store = http_request.app.state.session_store

    response = store.refresh(
        request.refresh_token.get_secret_value()
    )

    if response is None:
        raise HTTPException(
            status_code=401,
            detail="登录已失效，请重新登录。",
        )

    return response

@app.get(
    "/v1/auth/me",
    response_model=AuthUser,
)
def get_me(
    user: AuthUser = Depends(get_current_user)
) -> AuthUser:
    return user

async def require_generation_access(
    http_request: Request,
    generation_id : UUID,
    user_id: UUID,
) -> GenerationSnapshot:
    generation_store = http_request.app.state.generation_store
    conversation_store = http_request.app.state.conversation_store

    snapshot = await run_in_threadpool(
        generation_store.get,
        generation_id,
    )

    if snapshot is None:
        raise HTTPException(
            status_code=404,
            detail="会话不存在或无权访问。",
        )

    conversation = await run_in_threadpool(
        conversation_store.get,
        snapshot.conversation_id,
        user_id,
    )

    if conversation is None:
        raise HTTPException(
            status_code=404,
            detail="会话不存在或无权访问。",
        )

    return snapshot

@app.get(
    "/v1/generations/{generation_id}",
    response_model=GenerationSnapshot,
)
async def get_generation(
    generation_id: UUID,
    http_request: Request,
    user: AuthUser = Depends(get_current_user)
):
    return await require_generation_access(
        http_request,
        generation_id,
        user.id
    )

@app.post("/v1/echo")
def echo(request: EchoRequest):
    question = request.question.strip()

    if not question:
        raise HTTPException(
            status_code=422,
            detail="问题不能只包含空白字符"
        )

    return {
        "question": question,
        "message": "收到问题: " + question,
        "question_length": len(question)
    }

@app.post("/v1/ask", response_model=AskResponse)
async def ask(
    request: AskRequest,
    http_request: Request,
):
    question = request.question.strip()

    if not question:
        raise HTTPException(
            status_code=422,
            detail="问题不能只包含空白字符",
        )

    history = prepare_history(request)

    if not os.getenv("DEEPSEEK_API_KEY"):
        raise HTTPException(
            status_code=503,
            detail="服务器尚未配置 AI 服务",
        )

    chunks = await retrieve_chunks(
        http_request,
        question,
        history,
    )

    try:
        response = await ask_question(question, chunks, history)
    except APITimeoutError as error:
        raise HTTPException(
            status_code=504,
            detail="AI 回答超时，请稍后重试",
        ) from error
    except APIError as error:
        raise HTTPException(
            status_code=502,
            detail="AI 服务请求失败，请稍后重试",
        ) from error

    answer = response.content

    if not isinstance(answer, str) or not answer.strip():
        raise HTTPException(
            status_code=502,
            detail="AI 服务未返回有效文本",
        )

    return AskResponse(
        question=question,
        answer=answer,
    )

@app.post("/v1/ask/stream")
async def ask_stream(
    request: AskRequest,
    http_request: Request,
):
    question = request.question.strip()

    if not question:
        raise HTTPException(
            status_code=422,
            detail="问题不能只包含空白字符",
        )

    history = prepare_history(request)

    if not os.getenv("DEEPSEEK_API_KEY"):
        raise HTTPException(
            status_code=503,
            detail="服务器尚未配置 AI 服务",
        )

    chunks = await retrieve_chunks(
        http_request,
        question,
        history,
    )

    sources: list[str] = []
    source_chunks: list[dict[str, object]] = []

    for chunk in chunks:
        source_chunks.append(asdict(chunk))

        if chunk.path not in sources:
            sources.append(chunk.path)

    async def events():
        has_text = False

        try:
            async for text in stream_question(question, chunks, history):
                if text.strip():
                    has_text = True

                yield encode_sse("delta", {"text": text})
        except StreamAnswerError as error:
            yield encode_sse(
                "error",
                {"message": str(error)},
            )
            return

        except (APITimeoutError, TimeoutError):
            yield encode_sse(
                "error",
                {"message": "等待 AI 回答超时，请稍后重试。"},
            )
            return

        except APIError:
            yield encode_sse(
                "error",
                {"message": "AI 服务请求失败，请稍后重试。"},
            )
            return

        if not has_text:
            yield encode_sse(
                "error",
                {"message": "AI 服务未返回有效文本。"},
            )
            return

        yield encode_sse(
            "done",
            {
                "sources": sources,
                "source_chunks": source_chunks,
            },
        )

    return StreamingResponse(
        events(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
        },
    )

@app.post(
    "/v1/generations",
    response_model=GenerationSnapshot,
    status_code=202,
)
async def create_generation(
    request: CreateGenerationRequest,
    http_request: Request,
    user: AuthUser = Depends(get_current_user),
):
    conversation_store = http_request.app.state.conversation_store

    conversation = await run_in_threadpool(
        conversation_store.get,
        request.conversation_id,
        user.id
    )

    if conversation is None:
        raise HTTPException(
            status_code=404,
            detail="会话不存在或无权访问。",
        )

    question = request.question.strip()

    if not question:
        raise HTTPException(
            status_code=422,
            detail="问题不能只包含空白字符",
        )

    history = prepare_history(request)

    task_input = GenerationInput(
        question=question,
        history=history,
    )

    snapshot = GenerationSnapshot(
        id=request.request_id,
        conversation_id=request.conversation_id,
        question_message_id=uuid4(),
        answer_message_id=uuid4(),
        state=GenerationState.queued,
    )

    try:
        return await run_in_threadpool(
            http_request.app.state.generation_store.create_or_get,
            snapshot,
            task_input,
        )
    except GenerationConflictError as error:
        raise HTTPException(
            status_code=409,
            detail=str(error),
        ) from error

@app.post(
    "/v1/generations/{generation_id}/stop",
    response_model=GenerationSnapshot,
)
async def stop_generation(
    generation_id: UUID,
    http_request: Request,
    user: AuthUser = Depends(get_current_user)
):
    await require_generation_access(
        http_request,
        generation_id,
        user.id
    )

    snapshot = await run_in_threadpool(
        http_request.app.state.generation_store.request_stop,
        generation_id,
    )

    if snapshot is None:
        raise HTTPException(
            status_code=404,
            detail="生成任务不存在",
        )

    return snapshot

@app.get("/v1/generations/{generation_id}/events")
async def subscribe_generation(
    generation_id: UUID,
    http_request: Request,
    user: AuthUser = Depends(get_current_user)
):
    store = http_request.app.state.generation_store

    initial = await require_generation_access(
        http_request,
        generation_id,
        user.id
    )

    async def events():
        snapshot = initial
        last_revision = -1

        loop = asyncio.get_running_loop()
        last_sent_at = loop.time()

        while True:
            if await http_request.is_disconnected():
                return

            if snapshot.revision > last_revision:
                yield encode_sse(
                    "snapshot",
                    snapshot.model_dump(mode="json"),
                )

                last_revision = snapshot.revision
                last_sent_at = loop.time()

            elif loop.time() - last_sent_at > 15:
                yield ":ping\n\n"
                last_sent_at = loop.time()

            if snapshot.state in {
                GenerationState.completed,
                GenerationState.cancelled,
                GenerationState.failed,
                GenerationState.interrupted,
            }:
                return

            await asyncio.sleep(0.25)

            snapshot = await run_in_threadpool(
                store.get,
                generation_id,
            )

            if snapshot is None:
                yield encode_sse(
                    "error",
                    {"message": "生成任务不存在"},
                )
                return

    return StreamingResponse(
        events(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
        },
    )

@app.post(
    "/v1/conversations",
    response_model=ConversationSummary,
)
async def create_conversation(
    request: CreateConversationRequest,
    http_request: Request,
    user: AuthUser = Depends(get_current_user)
):
    store = http_request.app.state.conversation_store

    try:
        return await run_in_threadpool(
            store.create_or_get,
            request,
            user.id
        )
    except PermissionError as error:
        raise HTTPException(
            status_code=404,
            detail="会话不存在或无权访问。",
        ) from error
    except ValueError as error:
        raise HTTPException(
            status_code=422,
            detail=str(error),
        ) from error

@app.get(
    "/v1/conversations",
    response_model=list[ConversationSummary],
)
async def list_conversations(
    http_request: Request,
    user: AuthUser = Depends(get_current_user)
):
    store = http_request.app.state.conversation_store
    return await run_in_threadpool(
        store.list_conversations,
        user.id
    )

@app.get(
    "/v1/conversations/{conversation_id}",
    response_model=ConversationSummary,
)
async def get_conversation(
    conversation_id: UUID,
    http_request: Request,
    user: AuthUser = Depends(get_current_user),
):
    store = http_request.app.state.conversation_store

    conversation = await run_in_threadpool(
        store.get,
        conversation_id,
        user.id
    )

    if conversation is None:
        raise HTTPException(
            status_code=404,
            detail="会话不存在",
        )

    return conversation

@app.get(
    "/v1/conversations/{conversation_id}/messages",
    response_model=list[ConversationMessage],
)
async def list_conversation_messages(
    conversation_id: UUID,
    http_request: Request,
    user: AuthUser = Depends(get_current_user),
):
    store = http_request.app.state.conversation_store

    conversation = await run_in_threadpool(
        store.get,
        conversation_id,
        user.id
    )

    if conversation is None:
        raise HTTPException(
            status_code=404,
            detail="会话不存在",
        )

    return await run_in_threadpool(
        store.list_messages,
        conversation_id,
    )

@app.get(
    "/v1/conversations/{conversation_id}/active-generation",
    response_model=ConversationGenerationRecovery | None,
)
async def get_conversation_active_generation(
    conversation_id: UUID,
    http_request: Request,
    user: AuthUser = Depends(get_current_user)
):
    conversation_store = (http_request.app.state.conversation_store)
    generation_store = (http_request.app.state.generation_store)
    conversation = await run_in_threadpool(
        conversation_store.get,
        conversation_id,
        user.id
    )

    if conversation is None:
        raise HTTPException(
            status_code=404,
            detail="会话不存在",
        )

    snapshot = await run_in_threadpool(
        generation_store.get_active,
        conversation_id,
    )

    if snapshot is None:
        return None

    task_input = await run_in_threadpool(
        generation_store.get_input,
        snapshot.id,
    )

    if task_input is None:
        raise HTTPException(
            status_code=500,
            detail="生成任务输入数据缺失",
        )

    history = [
        HistoryMessage(
            role="user" if role == "human" else "assistant",
            content=content,
        )
        for role, content in task_input.history
    ]

    return ConversationGenerationRecovery(
        snapshot=snapshot,
        request=CreateGenerationRequest(
            conversation_id=conversation_id,
            request_id=snapshot.id,
            question=task_input.question,
            history=history,
        )
    )
