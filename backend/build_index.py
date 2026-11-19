from pathlib import Path

import chromadb
from sentence_transformers import SentenceTransformer
from argparse import ArgumentParser
from uuid import uuid4
from collections import deque

from repo_context import CodeChunk, load_code_chunks
from source_archive import load_zip_code_chunks
from source_snapshot_store import SourceSnapshot, SourceSnapshotStore
from user_store import UserStore

INDEX_PATH = Path(__file__).resolve().parent / ".chroma"
COLLECTION_NAME = "devlens-code-e5-small-v1"

def split_for_embedding(
    chunks: list[CodeChunk],
    tokenizer,
    max_tokens: int,
) -> list[CodeChunk]:
    pending = deque(chunks)
    result: list[CodeChunk] = []

    while pending:
        chunk = pending.popleft()

        text = f"passage: {chunk.path}\n{chunk.content}"
        token_ids = tokenizer.encode(
            text,
            truncation=False,
        )

        if len(token_ids) <= max_tokens:
            result.append(chunk)
            continue

        lines = chunk.content.split("\n")

        if len(lines) <= 1:
            raise ValueError(
                f"单行源码过长：{chunk.path}:{chunk.start_line}"
            )

        middle = len(lines) // 2

        left = CodeChunk(
            path=chunk.path,
            start_line=chunk.start_line,
            end_line=chunk.start_line + middle - 1,
            content="\n".join(lines[:middle]),
        )

        right = CodeChunk(
            path=chunk.path,
            start_line=chunk.start_line + middle,
            end_line=chunk.end_line,
            content="\n".join(lines[middle:]),
        )

        pending.appendleft(right)
        pending.appendleft(left)

    return result

def build_index(
    chunks: list[CodeChunk],
    collection_name: str,
    *,
    refresh_existing: bool = False,
) -> int:
    if not chunks:
        raise ValueError("没有源码片段，停止建立索引。")

    print("正在加载 embedding 模型...")

    model = SentenceTransformer(
        "intfloat/multilingual-e5-small",
        device="cpu",
    )

    chunks = split_for_embedding(
        chunks,
        model.tokenizer,
        model.max_seq_length,
    )

    ids = []
    texts = []
    documents = []
    metadatas = []

    for chunk in chunks:
        chunk_id = f"{chunk.path}:{chunk.start_line}-{chunk.end_line}"

        text = f"passage: {chunk.path}\n{chunk.content}"

        token_ids = model.tokenizer.encode(
            text,
            truncation=False,
        )

        if len(token_ids) > model.max_seq_length:
            raise ValueError(
                f"片段过长，需要重新切分：{chunk_id}"
            )

        ids.append(chunk_id)
        texts.append(text)
        documents.append(chunk.content)
        metadatas.append({
            "path": chunk.path,
            "start_line": chunk.start_line,
            "end_line": chunk.end_line,
        })

    print(f"正在生成 {len(chunks)} 个源码向量……")

    vectors = model.encode(
        texts,
        normalize_embeddings=True,
    )

    client = chromadb.HttpClient(
        host="127.0.0.1",
        port=8001,
    )

    batch_size = min(128, client.get_max_batch_size())
    collection = client.create_collection(
        name=collection_name,
        embedding_function=None,
        configuration={"hnsw": {"space": "cosine"}},
        get_or_create=refresh_existing,
    )

    try:
        for start in range(0, len(ids), batch_size):
            end = start + batch_size
            collection.upsert(
                ids=ids[start:end],
                embeddings=vectors[start:end].tolist(),
                documents=documents[start:end],
                metadatas=metadatas[start:end],
            )

        if refresh_existing:
            current_ids = set(ids)
            stored_ids = collection.get(include=[])["ids"]
            stale_ids = [
                stored_id for stored_id in stored_ids
                if stored_id not in current_ids
            ]

            for start in range(0, len(stale_ids), batch_size):
                collection.delete(ids=stale_ids[start:start + batch_size])

        return collection.count()
    except Exception as error:
        if not refresh_existing:
            try:
                client.delete_collection(name=collection_name)
            except Exception as cleanup_error:
                error.add_note(f"清理失败的索引 {collection_name}：{cleanup_error}")
        raise

def main() -> None:
    parser = ArgumentParser(description="为 DevLens 源码建立索引")
    parser.add_argument("--zip", type=Path, help="要索引的本地 ZIP 文件")
    parser.add_argument("--owner-email", help="登记源码版本的 DevLens 账号邮箱")
    args = parser.parse_args()

    database_path = (Path(__file__).resolve().parent / ".data" / "generations.sqlite3")
    owner = None

    if args.owner_email is not None:
        if args.zip is None:
            parser.error("--owner-email 需要和 --zip 一起使用。")

        owner = UserStore(database_path).get_by_email(args.owner_email)
        if owner is None:
            parser.error("找不到该邮箱对应的 DevLens 账号。")

    if args.zip is None:
        collection_name = COLLECTION_NAME
        count = build_index(
            load_code_chunks(),
            collection_name,
            refresh_existing=True,
        )
    else:
        snapshot_id = uuid4()
        collection_name = f"zip-{uuid4().hex}"
        count = build_index(
            load_zip_code_chunks(args.zip),
            collection_name,
        )

        if owner is not None:
            store = SourceSnapshotStore(database_path)
            store.register_ready(
                SourceSnapshot(
                    id=snapshot_id,
                    owner_id=owner.id,
                    name=args.zip.stem,
                    collection_name=collection_name,
                )
            )
            print(f"源码版本 ID：{snapshot_id}")

    print(f"索引集合：{collection_name}")
    print(f"索引中的片段数量：{count}")

if __name__ == "__main__":
    main()