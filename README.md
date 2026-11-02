# DevLens

基于 UIKit、FastAPI 和 LangChain 的 iOS 开发助手。
已接入 DeepSeek，支持基于 DevLens 指定源码的流式问答，
支持从回答进入来源列表，查看本次提供给模型的源码片段及原始行号。
已接入本地向量索引、关键词与向量混合检索及重排。
后续计划完善检索质量与引用校验，并接入工具调用和 Crash 诊断。

## 已完成功能

- UIKit 聊天消息列表，区分用户问题与 AI 回答，保留 Canvas 预览
- 底部消息输入区，支持键盘避让、拖动和点击列表收起键盘
- 流式回答合并刷新，减少高频列表更新
- 生成时自动跟随最新内容，手动浏览旧消息时暂停跟随
- 生成中滑回底部附近恢复跟随，回答结束后可自由浏览
- “回到最新”按钮按滚动位置自动显示和隐藏
- MVVM 拆分、协议注入及成功/失败 Mock 服务
- 加载状态、重复提交拦截和中文错误提示
- LangChain 异步调用 DeepSeek
- 模拟器与 iPhone 真机 AI 问答联调
- SSE 流式回答，收到文本后实时更新 UIKit 页面
- 支持停止生成并保留已有回答，停止后可以重新提问
- 流式请求异常中断时保留已收到的内容，并显示错误提示
- 读取指定源码并附带真实行号，作为模型回答的上下文
- 每条成功回答保存对应的源码片段，支持点击查看来源列表
- 源码详情展示文件路径、原始行号和当次请求的源码内容
- 源码详情支持文本选择与复制、动态字体及系统浅色/深色外观
- 识别流式回答的长度限制及非正常结束，保留部分回答并提示
- 使用 multilingual-e5-small 生成向量，并通过 Chroma 持久化源码索引
- 结合关键词检索和向量检索，通过 RRF 合并候选，再使用 CrossEncoder 重排
- 服务启动时加载检索模型，同一服务进程内复用
- 普通问答、流式问答和命令行问答共用 CodeRetriever
- 聊天消息支持长按菜单复制
- AI 回答支持 Markdown 标题、正文、粗体、斜体、行内代码和代码块
- 支持有序列表、无序列表、嵌套列表和引用块
- 用户消息保留原文，不按 Markdown 渲染
- 代码块展示语言标签，支持复制代码及复制结果提示
- 流式更新时复用未变化的前缀内容块
- 来源通过独立按钮进入，正文长按支持复制消息
- 加载、停止和错误提示独立于 Markdown 正文，避免被未闭合代码块吞入
- Mock 服务覆盖正常回答、请求失败和流式中断场景
- 本地会话列表与聊天记录持久化
- 多轮问答传递历史消息，并结合历史问题辅助源码检索
- 服务端持久生成任务，支持幂等创建、查询和停止
- SSE 返回完整任务快照，重连时获取最新结果
- 页面重入、前后台切换及 App 重启后恢复原任务

当前支持基于混合检索与重排的多轮代码问答。
会话历史保存在 iOS 本地，生成任务及进度保存在服务端 SQLite。
离开页面或关闭 App 不会主动停止服务端生成，重新进入后获取最新快照。

历史消息目前有数量与长度限制，尚未实现历史摘要。
达到限制时会提示新建会话。
目前支持常用 Markdown 文本结构，尚未实现表格渲染和链接点击跳转。

## 当前代码库问答范围

当前索引覆盖以下三份源码：

- backend/main.py
- ios/DevLens/DevLens/APIClient.swift
- ios/DevLens/DevLens/QuestionViewModel.swift

源码按最多 40 行切片，相邻片段重叠 8 行，保留文件路径与原始行号。
使用 intfloat/multilingual-e5-small 生成向量，
并保存到本地 Chroma 索引 backend/.chroma。

默认检索流程：

1. 关键词检索和向量检索各取得最多 6 个候选。
2. 使用 RRF 合并排序，保留全部去重候选，最多 12 个。
3. 使用 cross-encoder/mmarco-mMiniLMv2-L12-H384-v1 重排。
4. 将最终前 3 个源码片段提供给 DeepSeek 生成回答。

关键词检索和向量检索均使用索引中保存的源码。
关键词方法仍是词项重合计数，尚未使用 BM25。
模型在本地 CPU 上运行，首次使用需要下载模型。

来源列表和详情页展示当次请求提供给模型的源码片段。
同一文件可能出现多个片段，分别保留行号。
这些来源不代表回答中的所有引用都经过自动校验。

检索返回候选不等于候选足以回答问题。
当前通过提示词要求模型在证据不足时明确说明；
尚未实现可靠性经过评测的拒答阈值或自动引用校验。
没有提供任何片段时，回答函数直接返回说明，不调用 AI。

当前仍可能发生漏检、排序不准确和引用错误。

建立索引时需要保留上述文件及仓库目录结构。
修改被索引的源码后，保持 Chroma 运行，
停止 API、worker 和查询程序，重新运行 build_index.py，
然后重新启动 API 和 worker。
本地索引目录已加入 Git 忽略规则。

## 后端测试

在已激活虚拟环境的 backend 目录执行：

```bash
python -m unittest discover -s tests -v
```

覆盖关键词排序、原始行号保留、无匹配时不调用模型，
以及 SSE 完成事件中的来源片段字段、同文件多个片段和空行保留。
测试不需要真实 API Key，不调用外部模型服务。

## 后端接口

| 方法 | 路径 | 用途 |
| --- | --- | --- |
| GET | /health | 健康检查 |
| POST | /v1/echo | 问题回传与输入校验 |
| POST | /v1/ask | AI 问答 |
| POST | /v1/ask/stream | SSE 流式 AI 问答 |
| POST | /v1/generations | 幂等创建生成任务 |
| GET | /v1/generations/{id} | 查询任务最新快照 |
| POST | /v1/generations/{id}/stop | 请求停止生成 |
| GET | /v1/generations/{id}/events | 订阅任务完整快照 |

AI 问答请求：

```json
{
  "question": "DevLens 如何处理只有空白字符的问题？请引用源码。"
}
```

`/v1/ask` 成功响应包含 `question` 和 `answer`。

`/v1/ask/stream` 使用相同的请求体，响应类型为 `text/event-stream`：
- `delta`：携带 `text`，表示新增回答片段。
- `done`：表示回答正常完成，携带 `sources` 文件路径数组和
  `source_chunks` 源码片段数组。每个片段包含 `path`、`start_line`、
  `end_line` 和 `content`。
- `error`：携带 `message`，表示生成失败。

当前 iOS 聊天页面使用 `/v1/generations` 任务接口。

创建请求包含 `conversation_id`、`request_id`、`question` 和
`history`。提交结果不确定时，使用相同 request_id 和原请求重试，
避免重复创建任务。

任务订阅使用 `snapshot` 事件，每次携带完整回答、来源、状态和版本。
客户端替换当前回答，不把完整快照作为 delta 追加。
每次重连直接返回最新快照；终态快照发送后关闭订阅。

断开订阅不会停止任务；停止生成需要调用独立停止接口。

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

运行时需要三个独立进程：Chroma、API 和生成 worker。
以下命令均在 backend 目录、已激活虚拟环境的终端执行。

### 终端一：启动 Chroma

```bash
chroma run --path .chroma --host 127.0.0.1 --port 8001
```

保持这个终端运行。

### 首次建立或更新索引

Chroma 启动后，在另一个终端执行：

```bash
python build_index.py
```

该命令完成后会退出。修改被索引源码后，需要重新建立索引。
更新索引前，应停止使用该索引的 API、worker 和查询程序。

可以单独验证检索，不调用 DeepSeek：

```bash
python query_index.py
```

### 终端二：启动 API

```bash
python -m uvicorn main:app --reload --env-file .env --host 0.0.0.0 --port 8000
```

等待 `Application startup complete` 后再使用 App。

### 终端三：启动生成 worker

```bash
python generation_worker.py
```

等待“后台执行器已就绪”。

API 接收创建、查询、订阅和停止请求；worker 负责领取任务、
检索源码、调用 AI 并保存生成进度。
只启动 API 而未启动 worker，新建任务会一直排队。

同一个任务数据库只运行一个 worker。
API 的 `--reload` 不会自动重启独立 worker；
修改 worker 代码后需要手动重启。

服务端任务数据库位于 backend/.data/generations.sqlite3。
Chroma、API 和 worker 运行期间分别保持终端开启。

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

聊天页面、消息输入区、来源列表和源码详情均保留 `#Preview`。
聊天页面和来源页面预览使用示例数据。
MockQuestionService 保留用于旧问答流程的模拟场景。

## 命令行验证模型

在已激活虚拟环境的 backend 目录运行：

```bash
python try_llm.py
```

按提示输入密钥和问题，可在终端实时查看回答片段。
当前流式验证脚本不展示 Token 用量。
