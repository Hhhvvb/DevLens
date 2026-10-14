import asyncio
import os
from getpass import getpass

from llm_service import ask_question

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
    response = await ask_question(question)

    print("\n模型回答：")
    print(response.content)

    print("\nToken 用量：")
    print(response.usage_metadata)

if __name__ == "__main__":
    asyncio.run(main())