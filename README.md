# DevLens

基于 UIKit、FastAPI 和 LangChain 的 iOS 开发助手。
目前已接入 DeepSeek，支持在 iPhone 中提问并获取 AI 回答。
后续计划实现代码库问答、RAG、工具调用和 Crash 诊断。

## 已完成功能

- UIKit 提问页面及 Canvas 预览
- MVVM 拆分、协议注入及成功/失败 Mock 服务
- 加载状态、重复提交拦截和中文错误提示
- LangChain 异步调用 DeepSeek
- 模拟器与 iPhone 真机 AI 问答联调

当前为单次问答，尚未实现多轮记忆、流式输出和代码库检索。

## 后端接口

| 方法 | 路径 | 用途 |
| --- | --- | --- |
| GET | /health | 健康检查 |
| POST | /v1/echo | 问题回传与输入校验 |
| POST | /v1/ask | AI 问答 |

AI 问答请求：

```json
{
  "question": "UIKit 中 delegate 怎么用？"
}
```

成功响应包含 `question` 和 `answer`。
问题长度限制为 1～3000 个字符，不接受纯空白内容。

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

按提示输入密钥和问题，可查看模型回答与 Token 用量。
密钥输入时不显示字符，粘贴后直接按回车。