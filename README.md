# Power-Reviewer

24/7 自动 code review agent —— **本地小模型当主力 worker,大模型(订阅)当大脑做升级深审,GitHub Actions 当编排层**。只产出 review / feedback / 建议,**不改代码**。

> 设计依据见 [`RESEARCH-24x7-code-review-agent.md`](./RESEARCH-24x7-code-review-agent.md)。

## 架构(结构①:两仓 + submodule)

```
Power-Reviewer/            ← 本仓(origin: jhfnetboy/Power-Reviewer)= 大脑/编排 + 你的 feature
├─ .github/workflows/      GitHub Actions 混合编排(免费托管 runner + 自托管 Mac runner)
│   └─ review.yml
├─ orchestrator/           本地模型 + 升级大脑的胶水层
│   ├─ litellm.config.yaml LiteLLM 统一端点(本地 Qwen)
│   ├─ run-review.sh       自托管 runner 入口:跑本地 review → 发 PR 评论
│   └─ .env.example
├─ kody-rules/             Policy-as-Code 规则(大白话,按目录生效)
├─ deterministic/          确定性层(Semgrep / 覆盖率 diff)配置
├─ scripts/
│   ├─ setup-fork.sh       【一次性】fork Kodus + 挂 submodule(需先 gh auth)
│   └─ register-runner.md  把 Mac 注册成 self-hosted runner 的步骤
└─ vendor/kodus/           ← git submodule(你 fork 的 Kodus;upstream=kodustech/kodus-ai)
```

## 三层职责

| 层 | 跑在哪 | 干什么 | 成本 |
|---|---|---|---|
| 确定性层 | GitHub 托管 runner(免费) | Semgrep / CodeQL(公开仓)/ lint / test / 覆盖率 diff → 硬证据 | 免费 |
| 本地 LLM 层 | 你的 Mac(self-hosted runner) | Qwen-Coder 在硬证据上做语义 review | 免费(本地) |
| 升级大脑层 | 你的 Mac,**官方 `claude -p` / `codex` CLI** | 复杂/安全关键 PR 深审 + 汇总,**严格限流** | 走订阅,省着用 |

> ⚠️ 合规红线:**绝不**把 Max/Codex 的 OAuth token 塞进 LiteLLM 或任何第三方工具(违反 2026-02 ToS)。升级大脑只走官方 CLI。详见研究文档 §1。

## 落地顺序

1. `gh auth login`(当前 token 失效 + 代理 7890 需排查)
2. `bash scripts/setup-fork.sh` —— fork Kodus 并挂为 submodule
3. 本地起模型:`ollama pull qwen2.5-coder:32b` → `ollama serve`
4. 起 LiteLLM:`litellm --config orchestrator/litellm.config.yaml --port 4000`
5. 按 `scripts/register-runner.md` 把 Mac 注册成带 `power-reviewer` 标签的 self-hosted runner
6. 在目标仓库启用 `.github/workflows/review.yml`,开一个测试 PR 验证闭环

## 状态

🚧 脚手架阶段。`vendor/kodus` 与实际 review 逻辑待 `setup-fork.sh` 跑通后接入;`run-review.sh` 中标 `TODO` 的 `kodus-ai-cr` 调用方式需对照其仓库文档核对。
