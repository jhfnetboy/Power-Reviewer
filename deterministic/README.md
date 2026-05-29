# 确定性层

跑在免费 GitHub 托管 runner 上,产出"硬证据"喂给本地 LLM 层(降幻觉、降噪)。
研究显示 LLM 在 SAST 结果上做后置过滤,可把误报从 ~92% 压到个位数。

| 工具 | 用途 | 公开仓 | 私有仓 |
|---|---|---|---|
| Semgrep OSS | SAST,PR 快反馈 | 免费 | 免费(自托管) |
| CodeQL | 深度语义安全分析 | 免费 | 需 GHAS(付费) |
| 覆盖率 diff | 揪"改了代码没加测试" | 免费 | 免费 |
| lint / typecheck | 风格 / 类型 | 免费 | 免费 |

- 公开仓:Semgrep + CodeQL 都上。
- 私有仓:用 Semgrep 替代 CodeQL。
- 自定义 Semgrep 规则放本目录,workflow 里 `--config ./deterministic`。

> 配置入口见 `../.github/workflows/review.yml` 的 `deterministic` job。
