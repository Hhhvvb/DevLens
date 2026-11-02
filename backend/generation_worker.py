import asyncio
import os
import fcntl
from contextlib import aclosing
from pathlib import Path

from dotenv import load_dotenv

from code_retriever import CodeRetriever
from generation_models import GenerationSnapshot, GenerationState
from generation_store import GenerationStore
from llm_service import stream_question
from retrieval_service import search_with_history

async def execute_generation(
    store: GenerationStore,
    retriever: CodeRetriever,
    snapshot: GenerationSnapshot,
) -> None:
    try:
        task_input = await asyncio.to_thread(
            store.get_input,
            snapshot.id,
        )

        if task_input is None:
            raise RuntimeError("任务输入不存在。")

        snapshot.source_chunks = await asyncio.to_thread(
            search_with_history,
            retriever,
            task_input.question,
            task_input.history,
        )

        saved = await asyncio.to_thread(
            store.save_progress,
            snapshot,
        )

        if saved is None:
            return

        snapshot = saved

        loop = asyncio.get_running_loop()
        last_saved_at = loop.time()

        async with aclosing(
            stream_question(
                task_input.question,
                snapshot.source_chunks,
                task_input.history,
            )
        ) as parts:
            async for text in parts:
                snapshot.answer += text

                if loop.time() - last_saved_at >= 0.5:
                    saved = await asyncio.to_thread(
                        store.save_progress,
                        snapshot,
                    )

                    if saved is None:
                        return

                    snapshot = saved
                    last_saved_at = loop.time()

        if not snapshot.answer.strip():
            raise RuntimeError("AI 未返回有效文本。")

        snapshot.state = GenerationState.completed

    except asyncio.CancelledError:
        snapshot.state = GenerationState.interrupted
        snapshot.error_message = "后台执行器已停止，回答中断。"

        await asyncio.shield(
            asyncio.to_thread(store.save_progress, snapshot)
        )

        raise

    except Exception as error:
        snapshot.state = GenerationState.failed
        snapshot.error_message = (
            f"生成失败：{type(error).__name__}, 请重试。"
        )

        print(
            "任务失败：",
            snapshot.id,
            type(error).__name__,
            flush=True,
        )

    finally:
        await asyncio.shield(
            asyncio.to_thread(store.finish_stop, snapshot)
        )

    saved = await asyncio.to_thread(
        store.save_progress,
        snapshot,
    )

    if saved is not None:
        print(
            "任务状态：",
            saved.id,
            saved.state.value,
            flush=True,
        )

async def run_generation(
    store: GenerationStore,
    retriever: CodeRetriever,
    snapshot: GenerationSnapshot,
) -> None:
    task = asyncio.create_task(
        execute_generation(store, retriever, snapshot)
    )

    try:
        while not task.done():
            current = await asyncio.to_thread(
                store.get,
                snapshot.id,
            )

            if (
                current is None
                or current.state == GenerationState.stop_requested
            ):
                task.cancel()

                await asyncio.gather(
                    task,
                    return_exceptions=True,
                )

                return

            await asyncio.sleep(0.25)

        await task

    finally:
        task.cancel()

        await asyncio.gather(
            task,
            return_exceptions=True,
        )

async def main() -> None:
    backend_path = Path(__file__).resolve().parent
    load_dotenv(backend_path / ".env")

    if not os.getenv("DEEPSEEK_API_KEY"):
        raise RuntimeError(
            "尚未配置 DEEPSEEK_API_KEY。"
        )

    store = await asyncio.to_thread(
        GenerationStore,
        backend_path / ".data" / "generations.sqlite3"
    )

    recovered_count = await asyncio.to_thread(store.recover_unfinished)

    print("已恢复遗留任务：", recovered_count, flush=True,)

    retriever = await asyncio.to_thread(CodeRetriever)

    print("后台执行器已就绪。", flush=True)

    while True:
        snapshot = await asyncio.to_thread(store.claim_next)

        if snapshot is None:
            await asyncio.sleep(0.5)
            continue

        print("开始任务：", snapshot.id, flush=True)

        await run_generation(store, retriever, snapshot)

if __name__ == "__main__":
    lock_path = (
        Path(__file__).resolve().parent
        / ".data"
        / "generation_worker.lock"
    )

    lock_path.parent.mkdir(
        parents=True,
        exist_ok=True,
    )

    with lock_path.open("a") as lock_file:
        try:
            fcntl.flock(
                lock_file.fileno(),
                fcntl.LOCK_EX | fcntl.LOCK_NB,
            )
        except BlockingIOError:
            raise SystemExit(
                "已有后台执行器正在运行，请先关闭它。"
            )

        try:
            asyncio.run(main())
        except KeyboardInterrupt:
            print("后台执行器已退出。", flush=True)
