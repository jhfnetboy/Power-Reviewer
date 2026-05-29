# 部署必读坑点(OpenCode + 本地 Ollama)

已尽量焊进本仓配置:

1. **Ollama 版本锁定** — 某些版本在 M 系有 GPU→CPU 降级 bug,速度暴跌。`brew pin ollama`,升级前先在测试 PR 验证 tok/s。
2. **webhook 不要同步等 LLM** — OpenCode 走 GitHub Actions(异步,GitHub 自己管队列/重试),不像自建 Flask 有 10s webhook 超时问题。这条在 OpenCode 路线下天然规避。
3. **macOS Jetsam 内存杀手** — 18~24GB 的 Ollama 第一个被杀。用 `deploy/com.power-reviewer.ollama.plist`(KeepAlive 自重启)+ `OLLAMA_KEEP_ALIVE=-1`。
4. **关 thinking** — Qwen3 thinking 每次多花 30s+。lens prompt 已聚焦、可在 prompt 里加 `/no_think`;复杂深审才开。
5. **无状态** — 每个 PR 全新 context。OpenCode 每次 run 独立,天然满足;别开持久会话累积历史。
6. **本地并发=1** — OpenCode orchestrator 并行 fan-out 多 lens 到同一 Ollama。64GB 上 24GB 模型,`OLLAMA_NUM_PARALLEL=1`(已设)串行执行避免 OOM;吞吐靠排队。默认只启 4 个高价值 lens(security/testing/docs/consistency),design/solid 关掉。
7. **代理 NO_PROXY** — Clash(7890)会吞掉 `localhost:11434` 请求。`NO_PROXY=localhost,127.0.0.1`(workflow 已设)。这也是 `gh` API 时好时坏的同源问题。
8. **tool call 不稳就提 num_ctx** — OpenCode 是 agentic、依赖 tool 调用;本地模型 num_ctx 太小会让 tool call 失败,提到 16k–32k。
