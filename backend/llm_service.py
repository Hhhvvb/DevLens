from langchain_core.messages import AIMessage
from langchain_deepseek import ChatDeepSeek

async def ask_question(question: str) -> AIMessage:
    model = ChatDeepSeek(
        model="deepseek-flash",
        timeout=60,
        max_retries=0,
        max_tokens=1024,
        extra_body={"thinking": {"type": "disabled"}}
    )

    messages = [
        (
            "system",
            "你是 DevLens，一名 iOS 开发助手。"
            "请用中文回答，提供必要的代码示例；不确定时明确说明。",
        ),
        ("human", question),
    ]

    response = await model.ainvoke(messages)
    return response