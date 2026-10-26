import os
import json
import asyncio

from openai import APIError, APITimeoutError
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field
from llm_service import ( ask_question, stream_question, StreamAnswerError )
from dataclasses import asdict
from contextlib import asynccontextmanager
from starlette.concurrency import run_in_threadpool
from code_retriever import CodeRetriever
from repo_context import CodeChunk
from typing import Literal
from hybrid_retrieval import fuse_rankings

@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.retriever = await run_in_threadpool(
        CodeRetriever
    )
    app.state.retrieval_lock = asyncio.Lock()

    try:
        yield
    finally:
        del app.state.retriever

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

def search_with_history(
    retriever: CodeRetriever,
    question: str,
    history: list[tuple[str, str]],
) -> list[CodeChunk]:
    queries = [question]

    for role, content in reversed(history):
        if role != "human":
            continue

        previous_question = content.strip()

        if not previous_question:
            continue

        if previous_question in queries:
            continue

        queries.append(previous_question)

        if len(queries) >= 3:
            break

    rankings: list[list[CodeChunk]] = []

    for query in queries:
        chunks = retriever.search(query)
        rankings.append(chunks)

    if len(rankings) == 1:
        selected_chunks = rankings[0]
    else:
        selected_chunks = fuse_rankings(rankings, top_k=3)

    return selected_chunks



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
