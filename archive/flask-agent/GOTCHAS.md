# 关键坑点(部署前必读)

来自实战,已焊进本仓配置:

1. **Ollama 版本锁定** — 某些版本在 M1/M2 有 GPU→CPU 降级 bug,速度暴跌。
   `brew pin ollama` 锁版本,别自动更新。升级前先在测试 PR 上验证 tok/s 没掉。
2. **GitHub webhook 10s 超时** — LLM 推理 7~30s,必须异步。`app.py` 立即返回 202,
   真正 review 进 RQ 队列。否则 GitHub 判超时反复重试,雪崩。
3. **macOS Jetsam 内存杀手** — 18~24GB 的 Ollama 是第一个被杀的。
   用 `deploy/com.power-reviewer.ollama.plist`(LaunchAgent,KeepAlive 自动重启)+ `OLLAMA_KEEP_ALIVE=-1`(模型常驻)。
4. **Thinking 模式默认关** — Qwen3 thinking 每次多花 30s+。普通 review 用 `/no_think` 前缀
   (`graph.py` 已加);复杂 bug 再手动开。
5. **无状态设计** — 每次 PR review 用全新 context,不保留对话历史,否则长期运行后推理质量漂移。
   `worker.py` 每次新建 state。

补充(同样会咬人):
6. **并发=1** — 64GB 上 24GB 模型,RQ worker 别开多并发,否则第二个请求触发换页/OOM。
   需要吞吐就排队,别并行。`OLLAMA_MAX_LOADED_MODELS=1` 已设。
7. **代理 NO_PROXY** — 你用 Clash(7890)。worker/ollama 调 `localhost:11434` 必须走直连,
   设 `NO_PROXY=localhost,127.0.0.1`,否则本地请求被代理吞掉。
   (这也是之前 `gh` API 时好时坏的同源问题。)
