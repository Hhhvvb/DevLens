from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

app = FastAPI(title="DevLens")
class EchoRequest(BaseModel):
    question: str = Field(min_length=1, max_length=3000)

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