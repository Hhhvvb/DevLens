from pathlib import Path

import chromadb
from sentence_transformers import SentenceTransformer

from repo_context import load_code_chunks

INDEX_PATH = Path(__file__).resolve().parent / ".chroma"
COLLECTION_NAME = "devlens-code-e5-small-v1"

def main():
    chunks = load_code_chunks()

    if not chunks:
        raise ValueError("没有源码片段，停止建立索引。")

    print("正在加载 embedding 模型...")

    model = SentenceTransformer(
        "intfloat/multilingual-e5-small",
        device="cpu",
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

    collection = client.get_or_create_collection(
        name=COLLECTION_NAME,
        embedding_function=None,
        configuration={
            "hnsw": {"space" : "cosine"},
        },
    )

    collection.upsert(
        ids=ids,
        embeddings=vectors.tolist(),
        documents=documents,
        metadatas=metadatas,
    )

    current_ids = set(ids)
    stored_ids = collection.get(include=[])["ids"]

    stale_ids = []

    for stored_id in stored_ids:
        if stored_id not in current_ids:
            stale_ids.append(stored_id)

    if stale_ids:
        collection.delete(ids=stale_ids)

    print("索引保存位置：", INDEX_PATH)
    print("索引中的片段数量：", collection.count())

if __name__ == "__main__":
    main()