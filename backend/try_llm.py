import asyncio
import os
from getpass import getpass

from llm_service import stream_question

from openai import APIError, APITimeoutError

async def main():
    if not os.getenv("DEEPSEEK_API_KEY"):
        api_key = getpass("请输入 DeepSeek API Key：").strip()

        if not api_key:
            raise ValueError("API Key 不能为空")

        if not api_key.isascii() or not api_key.isprintable():
            raise ValueError("密钥包含异常字符，请重新运行并粘贴后直接回车")

        if any(char.isspace() for char in api_key):
            raise ValueError("密钥内部不能包含空白字符")

        os.environ["DEEPSEEK_API_KEY"] = api_key

    question = input("请输入你的问题：").strip()
    if not question:
        raise ValueError("问题不能为空")

    print("正在请求 DeepSeek...")
    print("\n模型回答：")

    try:
        async for text in stream_question(question):
            print(text, end="", flush=True)
    except APITimeoutError:
        print("\n\n连接 AI 服务时发生网络超时，请稍后重试。")
    except TimeoutError:
        print("\n\n等待模型片段超时，请稍后重试。")
    except APIError as error:
        status_code = getattr(error, "status_code", None)
        print(f"\n\nAI 服务请求失败，状态码：{status_code or '无'}。")
    else:
        print("\n\n回答结束。")

if __name__ == "__main__":
    asyncio.run(main())
