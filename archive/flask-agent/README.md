# agent —— 轻量 PR review 服务(Flask + RQ + LangGraph + Ollama)

按推荐架构实现,**模式 A(GitHub 驱动)**,只评论不改代码。

```
GitHub PR 创建/更新
  → webhook → app.py(Flask,立即返回 202)        # 坑#2:别等 LLM
  → Redis + RQ 异步队列
  → worker.py → graph.py(LangGraph Agent)
       ├── fetch_diff   读 PR diff(+ 可选:GitHub Actions 跑出的 Semgrep/CodeQL SARIF)
       ├── analyze      Qwen-Coder via Ollama(/no_think、无状态)  # 坑#4 #5
       └── post_comment GitHub Reviews API 写评论(绝不改代码)
  → PR 评论出现
```

## 与 Kodus 的关系(已澄清)

`vendor/kodus` 是**重型 NestJS 平台**(需 Postgres/Mongo/RabbitMQ + Docker)。本服务**不运行 Kodus**,而是把它当**参考源**:借鉴它的 AST 上下文构建、KodyRules 规则格式、去重策略。轻量自研 = 省资源、全控制,正好对上你的取向。详见研究文档 §12 与本 PR 说明。

## 确定性层从哪来

仍走**免费 GitHub Actions 托管 runner**(Semgrep / CodeQL 公开仓免费),结果作为 SARIF artifact;`fetch_diff` 把它读进来喂给 `analyze`。这样硬证据不占你 Mac 算力,LLM 在证据上推理(降误报)。

## 跑起来

```bash
brew install redis && brew services start redis
python -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt
export GH_WEBHOOK_SECRET=... GITHUB_TOKEN=...
rq worker reviews &                 # 起 worker
gunicorn -w 2 -b 0.0.0.0:8000 app:app   # 起 webhook(前面挂 Cloudflare Tunnel 暴露)
```
Ollama 用 LaunchAgent 常驻(见 `../deploy/`,坑#3)。
