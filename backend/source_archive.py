import stat
from pathlib import Path, PurePosixPath
from zipfile import ZIP_DEFLATED, ZIP_STORED, ZipFile, ZipInfo

from repo_context import CodeChunk, split_code_file

MAX_ZIP_BYTES = 50 * 1024 * 1024
MAX_ZIP_ENTRIES = 10_000
MAX_EXPANDER_BYTES = 200 * 1024 * 1024
MAX_FILE_BYTES = 256 * 1024
MAX_SOURCE_BYTES = 20 * 1024 * 1024
MAX_SOURCE_FILES = 1_000
MAX_CHUNKS = 20_000

SOURCE_SUFFIXES = {".swift", ".py", ".md"}
SKIP_PARTS = {
    "__macosx", "__pycache__", "build", "deriveddata",
    "dist", "node_modules", "vendor", "venv",
}

def archive_path_for(entry: ZipInfo) -> PurePosixPath:
    name = entry.orig_filename
    path = PurePosixPath(name)

    if (
        not path.parts
        or path.is_absolute()
        or ".."in path.parts
        or any(char in name for char in ("\\", ":", "\x00"))
    ):
        raise ValueError("ZIP 包含无效的文件路径。")

    return path

def load_zip_code_chunks(archive_path: Path) -> list[CodeChunk]:
    if archive_path.stat().st_size > MAX_ZIP_BYTES:
        raise ValueError("ZIP 超过 50 MIB。")

    chunks: list[CodeChunk] = []
    seen_paths: set[PurePosixPath] = set()
    source_files = 0
    source_bytes = 0

    with ZipFile(archive_path) as archive:
        entries = archive.infolist()

        if len(entries) > MAX_ZIP_ENTRIES:
            raise ValueError("ZIP 中条目太多。")

        if sum(entry.file_size for entry in entries) > MAX_EXPANDER_BYTES:
            raise ValueError("ZIP 声明的解压大小超过 200 MiB。")

        for entry in entries:
            path = archive_path_for(entry)

            if path in seen_paths:
                raise ValueError("ZIP 中有重复的文件路径。")
            seen_paths.add(path)

            file_type = stat.S_IFMT(entry.external_attr >> 16)
            if file_type not in (0, stat.S_IFREG, stat.S_IFDIR):
                raise ValueError("ZIP 中包含符号链接或其他特殊文件。")

            if entry.flag_bits & 1:
                raise ValueError("目前只支持未加密的 ZIP。")

            if entry.is_dir() or file_type == stat.S_IFDIR:
                continue

            if any(
                part.startswith(".") or part.lower() in SKIP_PARTS
                for part in path.parts
            ):
                continue

            if (
                path.suffix.lower() not in SOURCE_SUFFIXES
                or entry.file_size > MAX_FILE_BYTES
            ):
                continue

            if entry.compress_type not in (ZIP_STORED, ZIP_DEFLATED):
                raise ValueError("源码文件的 ZIP 压缩方式暂不支持。")

            with archive.open(entry) as file:
                data = file.read(MAX_FILE_BYTES + 1)

            if len(data) > MAX_FILE_BYTES:
                raise ValueError("ZIP 内文件实际大小超过限制。")

            try:
                content = data.decode("utf-8-sig")
            except UnicodeDecodeError:
                continue

            if not content.strip() or "\x00" in content:
                continue

            source_files += 1
            source_bytes += len(data)
            if source_files > MAX_SOURCE_FILES or source_bytes > MAX_SOURCE_BYTES:
                raise ValueError("可索引源码的文件数或总大小超过限制。")

            chunks.extend(split_code_file(path.as_posix(), content))
            if len(chunks) > MAX_CHUNKS:
                raise ValueError("源码片段数量超过限制。")

    if not chunks:
        raise ValueError("ZIP 中没有可读取的 Swift、Python 或 Markdown 源码。")

    return chunks