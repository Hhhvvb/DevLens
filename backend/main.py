import os

from openai import APIError, APITimeoutError

from llm_service import ask_question

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

app = FastAPI(title="DevLens")
class EchoRequest(BaseModel):
    question: str = Field(min_length=1, max_length=3000)

class AskRequest(BaseModel):
    question: str = Field(min_length=1, max_length=3000)

class AskResponse(BaseModel):
    question: str
    answer: str

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