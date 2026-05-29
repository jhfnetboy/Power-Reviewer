# daemon —— 常驻 24h 代码质量助手(调度器)

把 Power-Reviewer 从"单仓 PR 审查"升级为**跨 org 的常驻后台助手**:持续发现该处理的工作、按优先级派给 OpenCode 本地审查、只给建议不改代码。

## 为什么是"轮询 daemon"而不是 webhook/Actions

你在**多个 org、别人的仓**里协作 review,那些仓你**没有 Actions 权限**——但 `gh search` 用你自己的身份在哪都能查。所以发现层用轮询(`discover.sh`)。你**自己拥有**的仓可另外加 `.github/workflows/opencode.yml` 降延迟,两者并存。

## 优先级模型

| 优先级 | 内容 | 来源 | 处理 |
|---|---|---|---|
| **P0** | 别人请我 review 的 PR + 我自己的 open PR | `gh search`(prbot 同款查询) | 每轮立即审 |
| P1 | (预留)活跃仓的新 push | — | 待实现 |
| **P2** | 背景巡检:文档完整性/一致性、整仓代码质量评估 | 三个 org 的活跃仓枚举 | 长线、空闲填充,每轮推进 `SWEEP_PER_CYCLE` 个 |

> PR 永远最优先;背景质量/文档巡检是长线任务,只在没有 P0 时蚕食推进。

## 组成

- `config.env` — 间隔/配额/orgs 来源(复用 `~/.config/prbot/repos.conf`)
- `discover.sh` — **已可跑**:gh 查询 → JSONL 工作项(P0 PR + P2 巡检仓)
- `reviewerd.sh` — 主循环:发现 → 去重(同 PR head SHA 不重审,防刷屏)→ 派 opencode → 记状态 →(限流)升级
- `../deploy/com.power-reviewer.reviewerd.plist` — launchd 常驻(崩溃自重启)

## 升级深审(回答"能不能调 claude/codex")

能,且你已装 `claude` 和 `codex` CLI。政策(见研究文档 §1/§15):
- **24h 粗审全用本地 omlx**(免费、不限量)。
- **升级只走官方 CLI**(`claude -p` / `codex exec`)——合规;**绝不**把订阅 OAuth token 喂给第三方工具。
- 注:你的全局配置已禁用 codex MCP(用 plugin/CLI 代替),所以走 `codex` CLI 而非 MCP。
- **不对所有 PR 自动二次深审**(烧周配额 + 自动化调订阅是 ToS 灰区)。只对本地审出 critical/高价值的 P0 PR 升级,且 `ESCALATE_DAILY_CAP` 当日硬上限。
- 更稳的默认仍是 **PR-as-medium**:bot 贴评论,你在 OpenCode/Claude Code 里对存疑项交互式深挖。

## 跑

```bash
bash daemon/discover.sh          # 先看发现层输出(JSONL),验证 gh 查询
bash daemon/reviewerd.sh         # 前台试跑主循环(Ctrl-C 停)
# 常驻:改 plist 里的路径 → cp ~/Library/LaunchAgents/ → launchctl load -w ...
```

## 待实现(诚实清单)

- `review_pr`:opencode headless 的真实调用(浅 clone + `gh pr checkout` + `opencode run`)待验证。
- `escalate_pr`:severity 判定 + 真正调 `claude -p`。
- P2 巡检:文档完整性/一致性/质量评估的 prompt + 巡检账本轮转。
- 接好后用本仓 PR(jhfnetboy/Power-Reviewer#1)当第一个真实审查目标自测。
