from code_retriever import CodeRetriever
from hybrid_retrieval import fuse_rankings
from repo_context import CodeChunk

def search_with_history(
    retriever: CodeRetriever,
    question: str,
    history: list[tuple[str, str]],
) -> list[CodeChunk]:
    queries = [question]

    for role, content in reversed(history):
        if role != "human":
            continue

        previous_question = content.strip()

        if not previous_question:
            continue

        if previous_question in queries:
            continue

        queries.append(previous_question)

        if len(queries) >= 3:
            break

    rankings: list[list[CodeChunk]] = []

    for query in queries:
        chunks = retriever.search(query)
        rankings.append(chunks)

    if len(rankings) == 1:
        selected_chunks = rankings[0]
    else:
        selected_chunks = fuse_rankings(rankings, top_k=3)

    return selected_chunks