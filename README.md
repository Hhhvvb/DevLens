# DevLens

**在同一个 AI 会话里结对读代码。**

DevLens 是一个 iOS 源码问答工具。排查接口时，你可以先让 AI 找相关实现，再点开源码核对。想让队友一起看，就邀请对方加入原会话。队友看到前面的问答和源码片段后，可以直接从自己关心的地方继续问。

[体验示例](#体验示例) · [项目功能](#项目功能) · [工作原理](#工作原理) · [快速开始](#快速开始) · [项目结构](#项目结构)

## 体验示例

一个人先确认空白输入会返回什么状态码，另一个人接着问错误提示。两个人共享同一段讨论，也都能打开前一轮回答的来源。

| 一个人先问 | 打开源码核对 | 队友在原会话追问 |
| :---: | :---: | :---: |
| <img src="docs/images/01-chat.png" width="240" alt="DevLens 回答空白问题会返回 422，并提供查看来源按钮"> | <img src="docs/images/02-source.png" width="240" alt="源码片段页显示 backend/main.py 的文件路径、原始行号和 /v1/echo 的空白输入校验"> | <img src="docs/images/03-shared.png" width="240" alt="共享会话中成员接着追问，DevLens 说明本轮源码片段不足以确认答案"> |

1. **把问题问到具体接口。**「`/v1/ask` 收到只含空白字符的 `question` 时，会返回什么状态码？」AI 回答 `422`，给出文件和行号。
2. **点开「查看来源」。** 回答下方可以打开这一轮检索到的多个片段。截图里打开的是 `backend/main.py` 中 `/v1/echo` 的校验片段。[第一轮回答引用的 `/v1/ask` 校验代码](backend/main.py#L523-L529)
3. **让队友顺着上一个问题追问。**「那这个分支返回的错误提示是什么？」这次检索只找到了 `/v1/ask` 的开头，模型在会话里说明了缺失的源码。两个人仍可打开前一轮的来源核对。

[用两个账号体验共享会话](docs/DEVELOPMENT.md#体验共享会话)

## 项目功能

[![DevLens 功能导图，包含共享会话、源码问答、流式回答、账号与好友](docs/images/devlens-features.png)](docs/images/devlens-features.png)

- **共享会话**。会话所有者可以邀请好友。接受邀请后，好友可以查看已有问答和参考源码，也可以继续提问。App 在前台同步会话变更和未读数。
- **源码问答**。来源页保留当轮提供给模型的具体代码，即使多个片段来自同一个文件，也能分别按原始行号查看。
- **流式回答**。聊天页逐步显示 Markdown 和代码块，支持复制代码或中途停止。离开 App 时，运行中的后端 worker 可以继续生成，重新进入会话就能看到最新进度。

## 工作原理

[![DevLens 工作原理图，两位成员通过 FastAPI 同步问答，生成 worker 从 SQLite 领取任务、从 Chroma 检索源码并调用 DeepSeek](docs/images/devlens-architecture.png)](docs/images/devlens-architecture.png)

1. **创建任务。** UIKit 客户端把问题和会话历史提交给 `/v1/generations`。FastAPI 检查会话访问权限，再把任务和消息持久化到 SQLite。同一个请求可以用原 `request_id` 重试。[生成入口](backend/main.py#L661)
2. **检索并生成。** worker 领取任务，用当前问题和最近的历史问题辅助检索。检索结合关键词与向量相似度，用 RRF 合并候选，再用 CrossEncoder 重排。命中的代码片段连同对话上下文交给 DeepSeek，worker 持续保存回答进度。[生成流程](backend/generation_worker.py) · [检索实现](backend/code_retriever.py) · [历史问题如何参与检索](backend/retrieval_service.py)
3. **让成员看见同一份进展。** 聊天页可以订阅生成任务的 SSE 快照，重连后收到最新版本。共享会话通过另一条 SSE 通道通知成员客户端有更新，客户端再从服务端读取消息。[任务快照](backend/main.py#L749) · [会话更新](backend/main.py#L993)

**当前范围。** 默认索引 DevLens 自身的三份源码。检索在本地运行，命中的源码和对话上下文会发送给 DeepSeek。来源页显示当轮给模型的片段，回答中的引用需要人工核对。[索引配置](backend/repo_context.py#L8-L12) · [模型上下文](backend/llm_service.py#L23)

## 快速开始

准备一台 Mac，安装 Xcode 27、iOS 27 模拟器运行时和 Python 3.12，并准备 DeepSeek API Key。检索模型首次运行时会下载到本地。首次注册需要 Mailpit 收取本地验证邮件。

### 1. 安装后端依赖

从仓库根目录执行以下命令。

```bash
cd backend
python3.12 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
```

在 `backend/.env` 中设置密钥。该文件已被 Git 忽略。

```dotenv
DEEPSEEK_API_KEY=你的密钥
```

### 2. 建立源码索引并启动服务

以下四条命令均在 `backend/` 下运行。新开终端后，先执行 `source .venv/bin/activate`。

| 顺序 | 命令 | 就绪标志 |
| --- | --- | --- |
| 1. Chroma | `chroma run --path .chroma --host 127.0.0.1 --port 8001` | 保持终端运行 |
| 2. 建索引 | `python build_index.py` | 输出索引片段数量后退出 |
| 3. API | `python -m uvicorn main:app --reload --env-file .env --host 127.0.0.1 --port 8000` | 出现 `Application startup complete` |
| 4. 生成 worker | `python generation_worker.py` | 出现「后台执行器已就绪」 |

建索引的终端可以接着运行 API。Chroma、API 和 worker 各自保持运行。打开 [健康检查](http://127.0.0.1:8000/health)，确认返回 `"status": "ok"`。

### 3. 在模拟器里完成第一次问答

1. 首次注册时，用 Homebrew 安装 Mailpit（`brew install mailpit`），在独立终端运行 `mailpit --listen 127.0.0.1:8025 --smtp 127.0.0.1:1025`。已有验证账号可以直接登录。
2. 用 Xcode 打开 `ios/DevLens/DevLens.xcodeproj`，选择 iPhone 模拟器，按 `⌘R`。
3. 在登录页点「创建账号」，提交后打开 [Mailpit 收件箱](http://127.0.0.1:8025) 复制验证 Token。回到 App 验证邮箱，然后登录。
4. 在「会话」点「新建」，输入[示例问题](#体验示例)。看到回答后点「查看来源」，打开任一个片段可看到文件路径和原始行号。

如果回答一直排队，先检查 worker 是否已就绪。用 iPhone 真机时，按 [真机配置](docs/DEVELOPMENT.md#iphone-真机) 调整 API 监听地址和 App 配置。

## 项目结构

```text
DevLens/
├── ios/DevLens/
│   ├── DevLens.xcodeproj
│   └── DevLens/
│       ├── Views/             # UIKit 聊天、会话、好友与源码页面
│       ├── ViewModels/        # 生成任务、会话事件与账号状态
│       ├── Services/          # API、SSE、Markdown 与认证
│       └── Storage/           # 本地会话缓存与登录凭据
├── backend/
│   ├── main.py                # FastAPI 路由与 SSE
│   ├── conversation_store.py  # 会话、成员、邀请与已读位置
│   ├── generation_store.py    # 持久化生成任务和会话消息
│   ├── generation_worker.py   # 执行任务并保存生成进度
│   ├── build_index.py         # 构建 Chroma 源码索引
│   ├── code_retriever.py      # 混合检索与重排
│   ├── llm_service.py         # 构造上下文并调用 DeepSeek
│   └── tests/
└── docs/
    ├── DEVELOPMENT.md        # 本地开发与接口指南
    └── images/                # Demo 的 iOS 模拟器截图
```

[开发指南](docs/DEVELOPMENT.md)包含双账号演示、真机配置、索引更新、后端接口和测试。服务启动后也可以查看 [FastAPI 接口文档](http://127.0.0.1:8000/docs)。
