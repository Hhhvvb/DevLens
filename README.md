# DevLens

基于 UIKit 的 iOS 开发辅助项目，目标是结合 FastAPI、RAG、
LangChain 和 LangGraph，实现代码库问答与 Crash 诊断。

## 当前进度

- FastAPI 健康检查接口：GET /health
- 问题回传与输入校验接口：POST /v1/echo
- UIKit 提问页面及 Canvas 预览
- URLSession 请求、JSON 编解码、加载状态与错误显示

目前接口用于验证前后端通信，尚未接入大模型。

## 本地启动后端

需要 Python 3.12。在仓库根目录执行：

```bash
cd backend
python3.12 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
python -m uvicorn main:app --reload --host 127.0.0.1 --port 8000
```

后端运行期间需要保持该终端开启。

健康检查地址：http://127.0.0.1:8000/health

## 运行 iOS 项目

1. 使用 Xcode 打开 ios/DevLens/DevLens.xcodeproj。
2. 选择一个 iPhone 模拟器。
3. 保持后端运行，按 Command + R。
4. 输入问题并提交，查看服务器回传结果。

当前 APIClient 使用 http://127.0.0.1:8000，适用于模拟器调试。

ViewController.swift 中的 #Preview 用于 Canvas 界面预览。