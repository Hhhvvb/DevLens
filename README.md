# DevLens
A UIKit iOS developer assistant with FastAPI, RAG, LangChain and LangGraph.

## 当前进度

已实现 FastAPI 健康检查接口：GET /health。

## 本地启动后端

需要 Python 3.12。在项目根目录执行：

```bash
cd backend
python3.12 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
python -m uvicorn main:app --reload
```

浏览器访问：http://127.0.0.1:8000/health

预期返回：

```json
{"status":"ok","service":"DevLens","version":"0.1.0"}
```