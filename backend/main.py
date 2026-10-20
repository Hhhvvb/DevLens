import os
import json

from openai import APIError, APITimeoutError
from fastapi import FastAPI, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field
from llm_service import ( ask_question, stream_question, StreamAnswerError )
from repo_context import search_code_chunks
from dataclasses import asdict

app = FastAPI(title="DevLens")
class EchoRequest(BaseModel):
    question: str = Field(min_length=1, max_length=3000)

class AskRequest(BaseModel):
    question: str = Field(min_length=1, max_length=3000)

class AskResponse(BaseModel):
    question: str
    answer: str

def encode_sse(event: str, data: dict[str, object]) -> str:
    payload = json.dumps(data, ensure_ascii=False)
    return f"event: {event}\ndata:{payload}\n\n"

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
async def ask(request: AskRequest):
    question = request.question.strip()

    if not question:
        raise HTTPException(
            status_code=422,
            detail="问题不能只包含空白字符",
        )

    if not os.getenv("DEEPSEEK_API_KEY"):
        raise HTTPException(
            status_code=503,
            detail="服务器尚未配置 AI 服务",
        )

    try:
        response = await ask_question(question)
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
async def ask_stream(request: AskRequest):
    question = request.question.strip()

    if not question:
        raise HTTPException(
            status_code=422,
            detail="问题不能只包含空白字符",
        )

    if not os.getenv("DEEPSEEK_API_KEY"):
        raise HTTPException(
            status_code=503,
            detail="服务器尚未配置 AI 服务",
        )

    chunks = search_code_chunks(question)

    sources: list[str] = []
    source_chunks: list[dict[str, object]] = []

    for chunk in chunks:
        source_chunks.append(asdict(chunk))

        if chunk.path not in sources:
            sources.append(chunk.path)

    async def events():
        has_text = False

        try:
            async for text in stream_question(question, chunks):
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
