import chromadb

from sentence_transformers import SentenceTransformer, CrossEncoder
from build_index import INDEX_PATH, COLLECTION_NAME
from repo_context import CodeChunk, search_code_chunks
from hybrid_retrieval import fuse_rankings

class CodeRetriever:
    def __init__(self):
        if not INDEX_PATH.exists():
            raise RuntimeError("索引目录不存在，请先运行 build_index.py 建立索引。")

        self.client = chromadb.PersistentClient(path=str(INDEX_PATH))

        self.collection = self.client.get_collection(name=COLLECTION_NAME, embedding_function=None)

        if self.collection.count() == 0:
            raise RuntimeError("索引中没有源码片段，请先运行 build_index.py 建立索引。")

        print("正在加载 embedding 模型...")

        self.embedding_model = SentenceTransformer(
            "intfloat/multilingual-e5-small",
            device="cpu",
        )

        print("正在加载 reranker 模型...")

        self.reranker = CrossEncoder(
            "cross-encoder/mmarco-mMiniLMv2-L12-H384-v1",
            device="cpu",
            max_length=512,
        )

    def search(self, question: str, top_k: int = 3) -> list[CodeChunk]:
        question = question.strip()

        if not question:
            raise ValueError("问题不能为空。")

        if top_k <= 0:
            raise ValueError("top_k 必须大于 0")

        count = self.collection.count()

        if count == 0:
            raise RuntimeError("索引为空，请重新建立索引。")

        candidate_count = max(6, top_k)

        query_text = f"query: {question}"

        token_ids = self.embedding_model.tokenizer.encode(
            query_text,
            truncation=False,
        )

        if len(token_ids) > self.embedding_model.max_seq_length:
            raise ValueError("问题超过模型输入长度，请缩短后重试。")

        query_vectors = self.embedding_model.encode(
            [query_text],
            normalize_embeddings=True,
        )

        result = self.collection.query(
            query_embeddings=query_vectors.tolist(),
            n_results=min(candidate_count, count),
            include=["documents", "metadatas"],
        )

        documents = result["documents"][0]
        metadatas = result["metadatas"][0]

        vector_chunks = []

        for document, metadata in zip(documents, metadatas):
            vector_chunks.append(
                CodeChunk(
                    path=metadata["path"],
                    start_line=metadata["start_line"],
                    end_line=metadata["end_line"],
                    content=document,
                )
            )

        stored = self.collection.get(
            include=["documents", "metadatas"],
        )

        index_chunks = []

        for document, metadata in zip(
            stored["documents"],
            stored["metadatas"]
        ):
            index_chunks.append(
                CodeChunk(
                    path=metadata["path"],
                    start_line=metadata["start_line"],
                    end_line=metadata["end_line"],
                    content=document,
                )
            )

        keyword_chunks = search_code_chunks(
            question,
            top_k=candidate_count,
            chunks=index_chunks,
        )

        merged_limit = (len(keyword_chunks) + len(vector_chunks))
        candidates = fuse_rankings([keyword_chunks, vector_chunks], top_k=merged_limit)

        if not candidates:
            return []

        pairs = []

        for chunk in candidates:
            passage = f"{chunk.path}\n{chunk.content}"

            token_ids = self.reranker.tokenizer.encode(
                question,
                passage,
                truncation=False,
            )

            if len(token_ids) > self.reranker.max_seq_length:
                raise RuntimeError(
                    "问题与源码片段合计过长，"
                    "请缩短问题或调整源码分块。"
                )

            pairs.append((question, passage))

        scores = self.reranker.predict(
            pairs,
            batch_size=2,
            show_progress_bar=False,
        )

        ranked_results = sorted(
            zip(candidates, scores),
            key=lambda item: item[1],
            reverse=True,
        )

        selected_chunks = []

        for chunk, score in ranked_results[:top_k]:
            selected_chunks.append(chunk)

        return selected_chunks