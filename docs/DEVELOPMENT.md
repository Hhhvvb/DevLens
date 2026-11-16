# DevLens 开发指南

先按 [README 的快速开始](../README.md#快速开始) 启动本地服务并完成一次问答。

## 体验共享会话

1. 准备两个已验证的测试账号 A 和 B。可以在同一个模拟器里切换账号。要观察实时同步，用两个客户端分别登录，例如模拟器和 [iPhone 真机](#iphone-真机)，并连接同一个后端。
2. 在「我的 → 好友」用 B 的邮箱发送好友申请，再用 B 接受。
3. 用 A 在「会话」中新建对话，发送 [示例问题](../README.md#体验示例)。回答出现后可以点「查看来源」核对源码。
4. 用 A 点聊天页右上角的邀请按钮并选择 B。B 在「会话 → 会话邀请」接受并进入原对话，也可以从「共享」列表再次打开。
5. 用 B 在原对话里继续追问。切回 A，确认能看到 B 的昵称和提问，以及 DevLens 的后续回答。

会话所有者可以邀请好友。好友接受后可以看到已有消息和回答提供的源码片段，并在同一会话里提问。App 在前台接收实时更新并刷新未读数，浏览到最新消息后记录已读位置。

## iPhone 真机

1. 让 iPhone 和 Mac 连接同一局域网。
2. 启动 API 时，将 [快速开始](../README.md#快速开始) 中的 `--host 127.0.0.1` 改为 `--host 0.0.0.0`。
3. 在 [APIClient.swift](../ios/DevLens/DevLens/Services/Networking/APIClient.swift) 中，将真机分支的 `baseURL` 改为 `http://<Mac 的局域网 IP>:8000`。在 [Info.plist](../ios/DevLens/DevLens/Info.plist) 的 `NSExceptionDomains` 中同步更新对应的 IP。
4. 用 iPhone Safari 打开该地址的 `/health`，确认能连接后再从 Xcode 运行 App。按需在 Signing & Capabilities 选择自己的签名团队，并在 App 请求时允许本地网络访问。

Mac 的 IP 变化后，更新 `baseURL` 和 `Info.plist` 中的对应配置。

## 源码索引

默认索引范围由 [`SOURCE_FILES`](../backend/repo_context.py#L8-L12) 定义。保留这些文件及相对路径，从仓库内运行建索引脚本。

- 每个片段最多 40 行，相邻片段重叠 8 行，保存文件路径和原始行号。
- 向量模型为 `intfloat/multilingual-e5-small`，结果保存在本地 Chroma 的 `backend/.chroma`。
- 单条检索默认通过关键词词项重合和向量相似度各取最多 6 个候选，用 RRF 合并去重，再由 `cross-encoder/mmarco-mMiniLMv2-L12-H384-v1` 重排，取前 3 个。多轮会话还会结合最近的问题检索。
- 检索模型在本地 CPU 运行，首次启动可能需要等待模型下载。问答请求将命中的片段、当前问题和对话上下文发送给 DeepSeek。没有检索片段时，后端直接返回提示。

来源页保留当次送入模型的片段，可能包含同一文件的不同位置。目前依靠提示词要求模型在证据不足时说明，引用准确性需要人工核验。历史消息有数量和长度限制，达到限制时需要新建会话。

### 更新或单独验证索引

修改索引覆盖的源码后，保持 Chroma 运行，停止正在使用索引的 API、worker 和查询程序。在 `backend/` 激活虚拟环境，运行 `python build_index.py`，然后重新启动 API 和 worker。

独立验证检索时，只需运行 Chroma 并建好索引。在 `backend/` 已激活的虚拟环境中执行下面的命令，输入问题即可查看命中的路径和原始行号范围。

```bash
python query_index.py
```

要从命令行验证 DeepSeek 流式回答，请运行 `python try_llm.py`。脚本使用已在环境中设置的 `DEEPSEEK_API_KEY`，否则会提示输入密钥。

## 后端接口

API 启动后，打开 [FastAPI 接口文档](http://127.0.0.1:8000/docs) 查看请求格式和账号、好友、会话等路由。

| 方法 | 路径 | 用途 |
| --- | --- | --- |
| GET | `/health` | 健康检查 |
| POST | `/v1/echo` | 问题回传与输入校验 |
| POST | `/v1/ask` | 普通问答 |
| POST | `/v1/ask/stream` | 流式问答 |
| POST | `/v1/generations` | 幂等创建生成任务 |
| GET | `/v1/generations/{id}` | 查询任务最新快照 |
| POST | `/v1/generations/{id}/stop` | 请求停止生成 |
| GET | `/v1/generations/{id}/events` | 订阅任务快照 |

### App 的生成任务

iOS 聊天页通过 `/v1/generations` 任务接口生成回答。创建请求包含 `conversation_id`、`request_id`、`question` 和 `history`。如果提交结果不确定，带相同的 `request_id` 和原请求重试。

SSE 的 `snapshot` 事件包含完整回答、来源、状态和版本。客户端用整份快照替换当前结果。重连后立即收到最新快照，终态发送后结束订阅。断开订阅时，worker 继续执行任务，用户可通过停止接口中止生成。

API 和 worker 共用 `backend/.data/generations.sqlite3`。同一个任务数据库只运行一个 worker。修改 worker 代码后需手动重启，API 的 `--reload` 只作用于 API。

### 直接调用问答接口

`/v1/ask` 和 `/v1/ask/stream` 均接受以下请求体。

```json
{
  "question": "DevLens 如何处理只有空白字符的问题？请引用源码。"
}
```

`/v1/ask` 的成功响应包含 `question` 和 `answer`。`/v1/ask/stream` 使用 `text/event-stream`，事件顺序如下。

- `delta` 提供新增的 `text`。
- `done` 提供 `sources` 和 `source_chunks`。每个片段包含 `path`、`start_line`、`end_line` 和 `content`。
- 生成失败时，以包含 `message` 的 `error` 事件结束。流开始前的输入校验失败返回 HTTP 422，缺少服务端密钥返回 HTTP 503。

## 开发验证

在 `backend/` 激活虚拟环境后运行后端测试。

```bash
python -m unittest discover -s tests -v
```

测试覆盖关键词排序、源码行号保留、无匹配时跳过模型调用，以及 SSE 完成事件中的多片段来源。可使用测试内的模拟数据执行。

Xcode 的聊天界面、输入区和来源页面提供 `#Preview`，可用于单独检查界面。旧问答流程的 `MockQuestionService` 支持模拟正常回答、请求失败和流式中断。
