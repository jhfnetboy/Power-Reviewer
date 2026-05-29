# Power-Reviewer

24/7 自动 code review —— **本地 Qwen 跑多维度审查(免费/不限量),订阅大模型按需做深审,只评论不改代码。**

底座选型:**OpenCode(provider-agnostic agent 运行时)+ 多 lens 编排**(借鉴 [opencode-review](https://github.com/cedricwider/opencode-review))。同一个工具,本地模型跑 24h 粗审、切订阅做深审。

> 完整调研与决策见 [`RESEARCH-24x7-code-review-agent.md`](./RESEARCH-24x7-code-review-agent.md)。

## 架构

```
被审查仓库 PR 创建/更新
  │
  ├─[免费 GitHub 托管 runner] deterministic.yml
  │     Semgrep + Slither(Solidity)+ test/coverage → 硬证据 SARIF artifact
  │
  └─[你 Mac 的 self-hosted runner] opencode.yml
        OpenCode `pr-reviewer` 编排器(本地 Qwen via Ollama):
          分诊 → 并行 fan-out 多 lens → 汇总去重 → 发 inline PR 评论
          ├─ security      OWASP + Web3/Solidity 专项(prompts/,本仓自定义)
          ├─ testing       改动是否有配套测试(vendor/opencode-review)
          ├─ docs          文档/注释同步(prompts/,本仓自加)
          ├─ consistency   代码库一致性(vendor/opencode-review)
          └─ design/solid  [默认关] 留给升级深审
  │
  └─[升级深审:你,按节奏] 在 OpenCode / Claude Code 里打开 PR,
        读 bot 评论,对 needs-human-brain 项交互式深挖+决策(PR-as-medium,合规)
```

## 关键文件

| 路径 | 作用 |
|---|---|
| `opencode.json` | OpenCode 配置:ollama 本地 provider + 多 lens(模型已改本地 Qwen) |
| `prompts/pr-review-security.md` | 安全 lens(OWASP + Web3/Paymaster/EIP-7702 专项) |
| `prompts/pr-review-docs.md` | 文档/注释同步 lens(第7项诉求,本仓自加) |
| `.github/workflows/deterministic.yml` | 免费托管 runner 跑 Semgrep/Slither |
| `.github/workflows/opencode.yml` | self-hosted Mac runner 跑 OpenCode 审查 |
| `deploy/com.power-reviewer.ollama.plist` | Ollama 常驻(Jetsam 自重启 + 串行,坑#3/#6) |
| `scripts/setup-opencode.sh` | 一键装齐(子模块/模型/常驻) |
| `scripts/register-runner.md` | Mac 注册 self-hosted runner |
| `docs/GOTCHAS.md` | 7 个部署必读坑点 |
| `vendor/opencode-review` | 参考底座(submodule),复用其标准 lens prompts + gh-pr-review skill |
| `archive/` | 早期方案(Flask+LangGraph agent、LiteLLM orchestrator),已被 OpenCode 取代,留作 fallback 参考 |

> Kodus 已移除:它是重型 NestJS 平台,不符合轻量取向;**该借鉴的概念(AST 上下文、KodyRules policy-as-code、去重)已记录在研究文档 §9**,实现则由 OpenCode 多 lens 覆盖。

## 落地顺序

1. `bash scripts/setup-opencode.sh`(装 OpenCode + 模型 + Ollama 常驻)
2. 本地试跑:在某 git 仓内 `opencode run --agent pr-reviewer "Review current branch against main."`
3. 按 `scripts/register-runner.md` 注册 self-hosted runner(标签 `power-reviewer`)
4. 把两个 workflow 放进首个目标仓,开测试 PR 验证端到端

## 合规红线

升级深审**不在配置里自动调订阅**(违反 2026-02 ToS + 烧周配额)。深审走 **PR-as-medium**:bot 贴评论,你本人在 OpenCode/Claude Code 里交互式处理。详见研究文档 §1、§15。

## 状态

🚧 配置就位,待验证:`opencode.yml` 里 `anomalyco/opencode/github` action 的真实输入参数需对实(已标 TODO);确定性层的 test/coverage 步骤待按首个目标仓语言补全。
