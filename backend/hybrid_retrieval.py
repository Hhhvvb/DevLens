from repo_context import CodeChunk

def fuse_rankings(
        rankings: list[list[CodeChunk]],
        top_k: int = 6,
) -> list[CodeChunk]:
    if top_k <= 0:
        raise ValueError("top_k 必须大于 0")

    scores = {}

    for ranking in rankings:
        for rank, chunk in enumerate(ranking, start=1):
            previous_score = scores.get(chunk, 0.0)
            scores[chunk] = previous_score + 1 / (60 + rank)

    ranked_chunks = sorted(
        scores,
        key=lambda chunk: scores[chunk],
        reverse=True,
    )

    return ranked_chunks[:top_k]