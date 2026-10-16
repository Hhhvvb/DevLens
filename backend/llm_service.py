from collections.abc import AsyncIterator

from langchain_core.messages import AIMessage
from langchain_deepseek import ChatDeepSeek

def create_model() -> ChatDeepSeek:
    return ChatDeepSeek(
        model="deepseek-flash",
        timeout=60,
        stream_chunk_timeout=60,
        max_retries=0,
        max_tokens=1024,
        extra_body={"thinking": {"type": "disabled"}},
    )

def create_message(question: str) -> list[tuple[str, str]]:
    return [
        (
            "system",
            "你是 DevLens，一名 iOS 开发助手。"
            "请用中文回答，提供必要的代码示例；不确定时请说明原因。",
        ),
        ("human", question),
    ]

async def ask_question(question: str) -> AIMessage:
    model = create_model()
    messages = create_message(question)

    return await model.ainvoke(messages)

async def stream_question(question: str) -> AsyncIterator[str]:
    model = create_model()
    messages = create_message(question)

    async for chunk in model.astream(messages):
        text = chunk.content

        if isinstance(text, str) and text:
            yield text
