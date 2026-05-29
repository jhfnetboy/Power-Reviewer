# Power-Reviewer

24/7 自动 code review —— **本地 Qwen 跑多维度审查(免费/不限量),订阅大模型按需做深审,只评论不改代码。**

当前方案:**轮询 daemon + 本地 omlx 直评**(Qwen3-Coder-30B-A3B,纯补全不用工具调用,对本地模型最稳)。OpenCode 多 lens agentic 编排为可选进阶路线(tool-call 在 Qwen3-Coder 上已验证可行)。

> 完整调研与决策见 [`RESEARCH-24x7-code-review-agent.md`](./RESEARCH-24x7-code-review-agent.md)。

## 工作流程(daemon 每轮做什么)

常驻脚本 `daemon/reviewerd.sh` 每 `POLL_INTERVAL`(默认 300s)跑一圈:

1. **发现**(`daemon/discover.sh`,用 `gh search`):
   - **P0a** 别人请我 review 的 PR — `gh search prs --review-requested=@me`(**按「@我」全局找,不限 org**)
   - **P0b** 我自己的 open PR — `gh search prs --author=@me`
   - **P2** `~/.config/prbot/repos.conf` 里 3 个 org(AAStarCommunity/AuraAIHQ/MushroomDAO)近 90 天活跃仓 → 整仓质量/文档背景巡检(**待实现**)
2. **优先级 + 去重**:先 P0;同一 PR 的同一 commit(head SHA)已审过就跳过(`seen.tsv`);每轮最多审 `MAX_REVIEWS_PER_CYCLE`(默认 3)个新 PR,其余下轮继续。
3. **直评**(`review/direct_review.py`,逐个 PR):
   - `gh pr diff` 取改动(超 `MAX_DIFF_CHARS` 截断)
   - 逐 lens(security / testing / docs / consistency)把 diff 发给本地 omlx 模型 → 结构化 JSON findings(**纯 chat completion,不用工具调用**)
   - 跨 lens 语义去重 + 降噪(跳过生成/机械文件、按严重度排序、inline 封顶 `MAX_INLINE`)
   - `gh api .../reviews` 发 inline review(`event=COMMENT`,**只评论不改代码**);`DRY_RUN=1` 时只打印不发
4. **记状态**:该 PR 的 head SHA 写入 `seen.tsv`(防重复刷屏)
5. **睡 `POLL_INTERVAL`** → 回到第 1 步

> 一句话:`gh 发现 PR → gh 取 diff → omlx 逐维度审 → gh 发评论`,纯本地、只评不改、按 SHA 去重、限流防刷屏。
>
> **范围澄清**:现在真正审的 PR 是**按「@我」全局找的**(我被请审的 + 我开的),**不限**那 3 个 org;3 个 org 的范围是给将来的**整仓背景巡检(P2)**用的。
>
> **升级深审**(复杂/安全关键)走 **PR-as-medium**:bot 贴评论,你在 Claude Code/Codex 里交互式深挖——合规且不烧订阅配额(见研究文档 §15)。

## 两个审查模式(两个"产品",`.env` 里 `REVIEW_MODE` 切换)

| | **direct(默认)** | **opencode(agentic)** |
|---|---|---|
| 怎么审 | 把 diff 直接喂模型 → 逐 lens 出 JSON | pr-reviewer 编排器**自主**读文件/grep/git diff,多 subagent 并行审 |
| 跨文件理解 | 弱(只看 diff) | 强(模型能主动翻仓库上下文) |
| 速度 | 快(~10-30s/PR) | **慢**(多 subagent × 多轮 tool-call,30B 上一个 PR 可能数分钟+) |
| 稳定性 | 高(纯补全) | 依赖模型 tool-call(Qwen3-Coder ✓,2.5-Coder ✗) |
| 适合 | **24h 全量 PR 巡审** | **重要/复杂 PR 按需深审** |
| 入口 | `run.sh` / daemon(`REVIEW_MODE=direct`) | `run-opencode.sh` / daemon(`REVIEW_MODE=opencode`) |

**产品① direct**:`bash run.sh`(24h 守在那审所有 PR)。
**产品② opencode**(先 `bash scripts/sync-opencode-global.sh` 同步全局配置):
```bash
bash run-opencode.sh owner/repo#123     # 深审某 PR(DRY_RUN=1 只打印)
bash run-opencode.sh                     # 审当前分支 → stdout
```
> 经验:opencode 能力强(模型自主探索),但在本地 30B 上**明显慢**——更适合你点名深审重要 PR,而非 24h 全量。两者共用同一套 lens prompts(`prompts/` + `vendor/opencode-review/prompts/`)。

## 确定性层(可选,免费 GitHub 托管 runner)

`.github/workflows/deterministic.yml`:PR 触发时跑 Semgrep + Slither(Solidity)+ 测试/覆盖率 → 把硬证据(SARIF)给本地 LLM 在其上推理(降误报)。daemon 直评也可读 `--evidence-file`。

## 关键文件

| 路径 | 作用 |
|---|---|
| **`run.sh`** | 手动前台跑(读 `.env`);多日挂着放 tmux |
| **`.env` / `.env.example`** | 全部配置(`.env` 真实值、gitignored;`.env.example` 模板) |
| **`daemon/reviewerd.sh`** | 常驻调度器主循环:发现→优先级→去重→派直评→记状态→睡 |
| **`daemon/discover.sh`** | 发现层:`gh search` 找 P0 PR(@我)+ 枚举 3 org 活跃仓(P2) |
| **`review/direct_review.py`** | 直评核心:diff→omlx 逐 lens→JSON→去重降噪→`gh` 发 inline review |
| `prompts/pr-review-security.md` | 安全 lens(OWASP + Web3/Paymaster/EIP-7702 专项) |
| `prompts/pr-review-docs.md` | 文档/注释同步 lens |
| `scripts/install-service.sh` | 把 reviewerd 装成 launchd 24h 常驻服务 |
| `deploy/*.plist` | launchd:reviewerd 服务 + Ollama 常驻 |
| `docs/GOTCHAS.md` | 部署必读坑点 |
| `.github/workflows/deterministic.yml` | (可选)免费托管 runner 跑 Semgrep/Slither |
| `opencode.json` / `.github/workflows/opencode.yml` / `scripts/setup-opencode.sh` | **(可选进阶)** OpenCode agentic 多 lens 路线 |
| `vendor/opencode-review` | 参考底座(submodule),lens prompts + gh-pr-review skill |
| `archive/` | 早期方案(Flask+LangGraph、LiteLLM),留作 fallback 参考 |

> Kodus 已移除(重型 NestJS,不符轻量取向);借鉴概念记录在研究文档 §9。

## 落地顺序

1. `cp .env.example .env` 并填好 `OMLX_API_KEY`(其余有默认值)
2. 确认 omlx 在跑、已加载 `REVIEW_MODEL` 指定的模型(`curl localhost:8088/v1/models`)
3. **手动跑观察**(DRY_RUN=1,只审不发):`tmux new -s pr 'bash run.sh'`
4. 质量满意 → `.env` 改 `DRY_RUN=0` 转真发
5. 想要开机自启/崩溃自重启 → `OMLX_API_KEY=… bash scripts/install-service.sh` 装成常驻服务

## 合规红线

升级深审**不在配置里自动调订阅**(违反 2026-02 ToS + 烧周配额)。深审走 **PR-as-medium**:bot 贴评论,你本人在 OpenCode/Claude Code 里交互式处理。详见研究文档 §1、§15。

## 状态

🚧 配置就位,待验证:`opencode.yml` 里 `anomalyco/opencode/github` action 的真实输入参数需对实(已标 TODO);确定性层的 test/coverage 步骤待按首个目标仓语言补全。
