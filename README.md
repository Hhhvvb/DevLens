# DevLens

基于 UIKit、FastAPI 和 LangChain 的 iOS 开发助手。
已接入 DeepSeek，支持基于 DevLens 指定源码的流式问答，
并在回答完成后展示本次提供给模型的文件。
后续计划实现自动代码检索、RAG、工具调用和 Crash 诊断。

## 已完成功能

- UIKit 提问页面及 Canvas 预览
- MVVM 拆分、协议注入及成功/失败 Mock 服务
- 加载状态、重复提交拦截和中文错误提示
- LangChain 异步调用 DeepSeek
- 模拟器与 iPhone 真机 AI 问答联调
- SSE 流式回答，收到文本后实时更新 UIKit 页面
- 支持停止生成并保留已有回答，停止后可以重新提问
- 流式请求异常中断时保留已收到的内容，并显示错误提示
- 读取指定源码并附带真实行号，作为模型回答的上下文
- 回答完成后展示后端提供的源码文件列表
- 识别流式回答的长度限制及非正常结束，保留部分回答并提示

当前支持单次流式问答，尚未实现多轮记忆和代码库检索。

## 当前代码库问答范围

每次请求固定读取以下三份文件：

- backend/main.py
- ios/DevLens/DevLens/APIClient.swift
- ios/DevLens/DevLens/QuestionViewModel.swift

当前尚未实现自动检索、向量数据库、RAG 或多轮记忆。

页面中的文件列表表示本次提供给模型的参考范围，
不代表每个文件都被回答引用，也不保证回答正确。
正文中的文件与行号引用由模型生成，目前尚未自动校验。

后端运行时需要保留上述文件及其仓库目录结构；
仅复制 backend 目录无法完成源码读取。

## 后端接口

| 方法 | 路径 | 用途 |
| --- | --- | --- |
| GET | /health | 健康检查 |
| POST | /v1/echo | 问题回传与输入校验 |
| POST | /v1/ask | AI 问答 |
| POST | /v1/ask/stream | SSE 流式 AI 问答 |

AI 问答请求：

```json
{
  "question": "DevLens 如何处理只有空白字符的问题？请引用源码。"
}
```

`/v1/ask` 成功响应包含 `question` 和 `answer`。

`/v1/ask/stream` 使用相同的请求体，响应类型为 `text/event-stream`：
- `delta`：携带 `text`，表示新增回答片段。
- `done`：表示回答正常完成，携带 `sources` 文件路径数组。
- `error`：携带 `message`，表示生成失败。

流开始前的输入校验失败返回 HTTP 422，缺少服务端密钥返回 HTTP 503。
流开始后的已处理错误通过 `error` 事件返回，不再发送 `done`。

## 本地启动后端

需要 Python 3.12。在仓库根目录执行：

```bash
cd backend
python3.12 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
```

在 backend 目录创建 `.env`，填入自己的 DeepSeek API Key：

```dotenv
DEEPSEEK_API_KEY=替换为你的真实密钥
```

`.env` 已加入 Git 忽略规则，密钥只由后端使用。

启动开发服务器：

```bash
python -m uvicorn main:app --reload --env-file .env --host 0.0.0.0 --port 8000
```

后端运行期间需要保持终端开启。

- 健康检查：http://127.0.0.1:8000/health
- 接口文档：http://127.0.0.1:8000/docs

## 运行 iOS 项目

用 Xcode 打开 `ios/DevLens/DevLens.xcodeproj`。

### 模拟器

选择 iPhone 模拟器，按 Command + R。
模拟器使用 `http://127.0.0.1:8000` 访问后端。

### iPhone 真机

1. iPhone 和 Mac 连接同一局域网。
2. 确认后端使用 `--host 0.0.0.0` 启动。
3. 将 APIClient.swift 中真机分支的 baseURL 改为 Mac 当前局域网 IP。
4. 同步更新 Info.plist 中对应的本地 HTTP 地址配置。
5. 先用 iPhone Safari 访问 `http://Mac的IP:8000/health`。
6. 选择真机并运行 App；如出现本地网络权限提示，允许访问。

局域网 IP 可能随网络变化，需要重新确认。
`0.0.0.0` 是后端监听地址，不是 App 请求地址。

ViewController.swift 保留 `#Preview`，可使用 Canvas 查看界面。

## 命令行验证模型

在已激活虚拟环境的 backend 目录运行：

```bash
python try_llm.py
```

按提示输入密钥和问题，可在终端实时查看回答片段。
当前流式验证脚本不展示 Token 用量。
