from argparse import ArgumentParser

from code_retriever import CodeRetriever
from build_index import COLLECTION_NAME

def main():
    parser = ArgumentParser(description="检索 DevLens 源码索引")
    parser.add_argument("--collection", default=COLLECTION_NAME)
    args = parser.parse_args()

    retriever = CodeRetriever(collection_name=args.collection)

    print("\n检索器已就绪，输入 /exit 退出。")

    while True:
        question = input("\n请输入代码库问题：").strip()

        if question == "/exit":
            break

        try:
            chunks = retriever.search(question)
        except (ValueError, RuntimeError) as error:
            print(f"检索失败：{error}")
            continue

        print("\n检索结果：")

        for rank, chunk in enumerate(chunks, start=1):
            print(
                f"{rank}. {chunk.path}:"
                f"L{chunk.start_line}-L{chunk.end_line}"
            )


if __name__ == "__main__":
    main()