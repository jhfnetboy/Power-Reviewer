# 24/7 自动 Code Review Agent —— 调研报告与方案建议

> 调研日期:2026-05-29 · 目标:用"本地小模型干活 + 大模型当大脑"的架构,搭一个 24 小时无人值守、只做 review/feedback 不改代码的 GitHub 仓库审查 agent。

---

## 0. 你的资源与诉求(确认理解)

**资源**
- Claude Code **Max** 订阅(Opus/Sonnet)
- Codex **Pro** 订阅(GPT-5.x-codex,ChatGPT 登录)
- 本地:Mac(M 系列)**64GB 统一内存**,可跑 8B~30B 级别本地模型,适合 24h 长时间循环
- 本地小模型:Qwen3-Coder 系列等

**诉求(review-only,不改代码)**
1. 24/7 自动 review 你**所有** GitHub 仓库
2. 提升代码质量 / 安全 / 降低 bug
3. 保证**业务一致性**(改动是否符合既有业务语义)
4. 揪小漏洞、小错误
5. 检查文档/注释是否同步更新
6. 检查单元测试 / E2E 测试是否完整
7. 产出:行内注释、问题清单、修改建议(**只建议,不动手**)

**期望工作模式**:本地小模型当主力 worker(免费、不限量、可 24h 跑);Codex / Claude Code 当"大脑"(规划 + 汇总 + 难点升级)。

---

## 1. 三条关键约束(先看这个,会改变方案设计)

### ⚠️ 约束一:订阅 token 不能塞进自研 agent(2026-02 ToS 更新)

Anthropic 在 2026 年 2 月更新了条款,新增 **Authentication and Credential Use** 政策:
> 通过 Free / Pro / Max 账户获得的 **OAuth token,仅限用于 Claude Code 和 claude.ai 本身**;把它用在"任何其他产品、工具或服务"里,即违反消费者条款。

**含义**:
- ✅ 合规:用**官方** `claude -p`(headless)或官方 `claude-code-action` —— 这些仍算"Claude Code 本身",走 Max 订阅额度。
- ❌ 违规 + 危险:把 OAuth token 抠出来塞进你自研的 orchestrator / LiteLLM / 第三方 review 框架去当 API 用。
- 💸 还有个坑:已有用户因 headless 误走 API 计费,两天烧掉 $1800+(issue #37686)。Codex Pro 同理。

**结论**:大模型当"大脑"这件事**可以做,但必须通过官方 CLI 入口**,而且要省着用(见约束二)。

### ⚠️ 约束二:Max/Codex 订阅有周级额度上限,24/7 全仓 grind 会把你自己饿死

- Max 是 5 小时窗口 + 7 天周期 双层限流,官方不公布具体数字。
- 官方建议:Max 订阅适合 **1~3 个稳定 agent**;**5+ 并行或通宵爆发用 API key**。
- 一个跨所有仓库、7×24 不停的 review loop,如果全用 Opus/Codex,**几乎一定**会耗尽额度,白天你交互式写代码时反而没配额了。

**结论**:**24h 不停的脏活累活必须压在本地模型上(零边际成本、不限量)**;订阅大脑只在"高价值/复杂/安全关键"的少数 PR 上、或人工点名时才介入。这恰好和你设想的分工一致 —— 只是要把比例摆对。

### ⚠️ 约束三:本地模型选型有"纸面 vs 实测"落差

- Qwen3-Coder-30B-A3B(MoE,3B 激活)纸面很美,但**当前 Ollama 上 MoE 的 GPU 利用率有已知问题**,实测速度优势被吃掉;Q4 下约 19~21GB。
- Qwen2.5-Coder-32B(dense,Q4 约 24GB)在 Ollama 上**利用率更稳**,FIM 补全也强,是更"无脑能用"的选择。
- Ollama 0.19(2026-03)已把 Apple Silicon 后端切到 **MLX**;追求速度可直接用 **MLX-LM**,新模型滞后时回退 llama.cpp。
- 搜索结果里大量 SEO 站点给的 tok/s、"95/100 评分"、"Qwen 3.6 35B"等数字**可信度低**,务必本地实测后再定。

---

## 2. 现成开源方案横评

| 方案 | 许可 | 自托管 | 本地模型 | Review-only | 上下文能力 | 适配度 | 备注 |
|---|---|---|---|---|---|---|---|
| **Kodus** (kodustech/kodus-ai) | AGPLv3 | ✅ 全栈 Docker | ✅ 任意 OpenAI 兼容端点 | ✅ 默认只评论 | **AST 图 + 跨文件上下文**(强) | ⭐⭐⭐⭐⭐ | 最贴需求:GitHub App + webhook + worker + pgvector,沙箱跑 review |
| **PR-Agent** (The-PR-Agent/pr-agent) | Apache-2.0 | ✅ | ✅ Ollama/LiteLLM 直连 | ✅ `/review` `/improve` | 中(偏 diff) | ⭐⭐⭐⭐ | 2026-04 转社区治理、license 回退 Apache;但**自托管配置有 4+ 月未修的已知 bug**,DIY 成分高 |
| **Kodus CR** (kodus-ai-cr) | AGPLv3 | ✅ CLI | ✅ | ✅ | 中 | ⭐⭐⭐ | Kodus 的 CLI 版,适合塞进自建流水线 |
| **Gito** (Nayjest/Gito) | OSS | ✅ | ✅ 本地模型则代码不出网 | ✅ 高置信度问题 | 中 | ⭐⭐⭐ | 主打"只报高置信度 bug/安全/可维护性",降噪好 |
| **Tabby** | OSS | ✅ | ✅ | 偏补全 | - | ⭐⭐ | 69.8k★,但核心是补全/助手,review 是附带 |
| **OpenReview** (vercel-labs) | OSS | Vercel | Claude 为主 | ❌ **会真改代码** | - | ⭐ | 直接 commit fix,**和你"只评不改"诉求冲突** |
| CodeRabbit / Qodo 云 / Greptile | 商业 SaaS | ❌(代码上云) | ❌ | ✅ | 强 | - | 体验最好但不满足"本地小模型/数据不出网" |

**结论**:**Kodus 是最贴你需求的现成底座**(自托管 + 模型可换 + 跨文件上下文 + 默认只评论 + 自带 webhook/PR 评论管线)。PR-Agent 更轻、更易二开,但要接受踩自托管配置坑。

---

## 3. 本地模型选型(64GB Mac)

按"24h 主力 worker"定位推荐,**优先级从上到下**:

| 模型 | 量化/显存 | 定位 | 说明 |
|---|---|---|---|
| **Qwen2.5-Coder-32B** | Q4 ~24GB | ✅ 首选稳妥主力 | Ollama 利用率稳、代码能力强、生态成熟,先用它把流程跑通 |
| **Qwen3-Coder-30B-A3B** | Q4 ~19-21GB | 主力候选 | 更新、agentic 更强;但确认你的 Ollama/MLX 版本已解决 MoE 利用率问题再上 |
| **Qwen3-Coder-Next** (80B-A3B) | 需量化压进 64GB | 进阶主力 | 2026-02 发布,3B 激活但能力对标大得多的模型;适合做"本地端的强 reviewer" |
| **GLM-4.x-Flash / 类似** | 小 | 路由/分诊用 | 跑得快,适合做"先粗筛哪些 PR 值得深审"的廉价分诊器 |
| Qwen3 8B 级 | ~6-8GB | 轻量任务 | 跑文档/注释同步检查、commit message 评估等低难度任务,省内存可多实例并行 |

**运行栈**:`Ollama`(最省心,0.19+ 用 MLX 后端)或 `MLX-LM`(最快)→ 前面挂 **LiteLLM** 暴露统一 OpenAI 兼容端点 → review 框架/编排器只对接这一个端点,以后换模型/加云端只改 LiteLLM 路由。

> 关于"千问3.6":搜索里出现 `QwenLM/Qwen3.6` 仓库与 `Qwen3-Coder-Next`(2026-02),但具体规格鱼龙混杂。**建议落地时本地实测 2~3 个候选**(同一批真实 PR 跑一遍,比命中率和速度)再锁定,别信 SEO 评分。

---

## 4. 推荐架构:Kodus 底座 + 本地主力 + 订阅大脑(三层)

```
                    GitHub App (webhook: PR opened / push)
                              │
                              ▼
        ┌──────────────────────────────────────────────┐
        │  Kodus self-hosted (Docker: web/api/worker/    │
        │  webhooks/RabbitMQ/Postgres+pgvector/Mongo)    │
        │  └─ AST 图 + 跨文件上下文 + 沙箱                  │
        └──────────────────────────────────────────────┘
                              │  调 LLM 走统一端点
                              ▼
        ┌──────────────────────────────────────────────┐
        │  LiteLLM 代理 (OpenAI 兼容,统一路由)            │
        └──────────────────────────────────────────────┘
              │                        │
              ▼ (默认/批量)            ▼ (升级:复杂/安全关键)
   ┌────────────────────┐   ┌──────────────────────────┐
   │ 本地模型 (Ollama/MLX)│   │ 订阅大脑 (官方 CLI 入口!)  │
   │ Qwen-Coder 主力      │   │ 人工点名 / 高价值 PR 才用   │
   │ 24h 不限量、零成本    │   │ Claude Code -p / Codex     │
   └────────────────────┘   └──────────────────────────┘
              ▲
              │ 喂确定性信号(降噪/补盲)
   ┌────────────────────────────────────────┐
   │ 确定性工具层(并行、先跑):                │
   │  • Semgrep(安全/SAST,PR 快反馈)        │
   │  • CodeQL(夜间深扫)                     │
   │  • 项目 lint / typecheck                 │
   │  • 测试覆盖率 diff(揪"改了代码没加测试") │
   └────────────────────────────────────────┘
```

**为什么这样分层**

1. **确定性工具先跑**:Semgrep/CodeQL/lint/覆盖率是 0 成本、0 幻觉的"硬证据"。研究显示 **LLM 对 SAST 结果做后置过滤,可把误报从 92% 压到 6.3%**;Semgrep 官方混合流水线对 IDOR 类逻辑漏洞做到"真阳性 ×8、误报 −50%"。**让 LLM 在硬证据基础上推理,而不是凭空找 bug**,是降噪关键。

2. **本地模型当 24h 主力**:绝大多数 PR 的常规审查(质量、注释/文档同步、测试是否齐、明显 bug)交给本地 Qwen-Coder,免费且不限量,正好填满你睡觉的时间。

3. **订阅大脑只做"升级 + 汇总"**:仅当本地模型判定"这个 PR 复杂/涉及安全/业务一致性存疑"时,才**通过官方 Claude Code / Codex CLI**(合规)升级深审,或对一批结果做高质量综合。**严格限流,避免吃光你的交互配额**(见 §1 约束二)。

4. **业务一致性**靠 Kodus 的 AST 图 + 跨文件上下文 + pgvector 检索相关代码/历史 PR,给模型"这块改动周边的业务语义",而不是只看 diff。

---

## 5. 三个落地路径(按投入/可控度排序)

### 路径 A —— Kodus 自托管(最快见效,推荐起步)
- `git clone kodustech/kodus-ai` → `docker compose up -d` → 配 GitHub App + webhook → LiteLLM 指向本地 Ollama。
- 1~2 天能跑通"PR 自动出评论"。先用 Qwen2.5-Coder-32B 把闭环建起来。
- 之后再逐步加:Semgrep 前置、覆盖率检查、订阅大脑升级路由。
- 代价:AGPLv3(自用无碍);webhook 需要公网入口(Cloudflare Tunnel / 内网穿透即可,Mac 在家也行)。

### 路径 B —— PR-Agent fork 二开(更轻、更可控)
- Apache-2.0,直接 `model = "ollama/qwen2.5-coder:32b"` + `[ollama] api_base`。
- 适合你想完全掌控 prompt、自定义 7 类检查维度的情况。
- 代价:已知自托管配置 bug,要做好踩坑/打补丁准备;跨文件上下文比 Kodus 弱,需自己补检索。

### 路径 C —— 完全自研 orchestrator(最贴你"大脑+worker"设想,最大自由度)
> `webhook → orchestrator → fan-out 本地子 agent → 汇总 → gh PR comment`

- 用一个轻量 Python/Node orchestrator(或直接 **Claude Code headless 当大脑**)做这套编排:
  1. 大脑读 PR diff + 元数据,**规划**该跑哪些维度(安全/测试/文档/业务一致性…)、哪些文件值得深审;
  2. **fan-out** 给多个本地小模型实例,每个负责一个维度或一批文件(64GB 可并行 1 个 30B + 几个 8B);
  3. 汇总去重、按 Critical/High/Medium/Low 分级;
  4. `gh pr comment` / `gh api` 发行内评论。
- 本仓库名 `Power-Reviewer` 看起来就是为这条路准备的。
- 业界已验证"大模型 planner + 小模型 worker"可省 **5~10× 成本**;多 agent 分维度审查(安全/性能/契约各一个独立 agent)是 2026 的主流做法。
- 代价:webhook、PR 评论、去重、状态管理全自己写;但**复用 `gh` CLI 能省掉大半管线**。

**我的建议**:**A 起步,C 演进**。先用 Kodus 1~2 天验证"24h 自动评论"这件事确实跑得动、质量能接受;跑通后,如果你想要更精细的"大脑分诊 + 多 worker 分维度"控制,再把编排逻辑迁到自研 `Power-Reviewer`(路径 C),Kodus 退化成"webhook 接收 + PR 评论发布"的管线,或干脆用 `gh` 自建。

---

## 6. 七项诉求 → 具体怎么落到检查项

| 诉求 | 主要手段 | 跑在哪 |
|---|---|---|
| 代码质量 | 本地模型 review + lint | 本地 worker(24h) |
| 安全 / 漏洞 | **Semgrep(PR)+ CodeQL(夜间)+ LLM 后置过滤降误报** | 确定性层 + 本地/大脑 |
| 降 bug | 本地模型 diff 审查 + 跨文件影响分析 | 本地 + Kodus AST |
| 业务一致性 | pgvector 检索相关代码/历史 PR 喂上下文 → 模型判断 | Kodus + 本地/大脑升级 |
| 文档/注释同步 | 轻量 8B 模型专项检查"改了 API 有没有改文档/注释" | 本地 8B(并行) |
| 单测完整 | **测试覆盖率 diff**(改了代码、覆盖率没涨/没新增测试 → 报)+ 模型评估测试质量 | 确定性层 + 本地 |
| E2E 完整 | 检测关键路径/接口改动是否有对应 E2E,缺失则建议 | 本地/大脑 |

> 全程**只产出评论/建议,不写回代码** —— 这正好降低风险:不需要 sandbox 写权限,不会误改,review-only 也让你更容易信任放它通宵跑。

---

## 7. 风险与注意事项清单

- **订阅合规**:大脑只走官方 `claude -p` / Codex CLI;**绝不**把 OAuth token 喂给自研/第三方框架(违反 ToS,见 §1)。
- **额度防爆**:给"升级到大脑"设硬性日配额上限 + 仅高价值 PR 触发;监控 5h/7d 用量,别饿死白天交互。
- **误计费**:确认 headless 走的是订阅而非 API key,避免重演 $1800 事故。
- **模型实测**:锁定本地模型前,用同一批真实 PR 横评命中率/速度,别信 SEO 数字。
- **降噪第一**:24h agent 最大失败模式是"刷屏低质评论没人看"。务必:① 先跑确定性工具给硬证据;② 只报高置信度问题(参考 Gito 思路);③ 分级 + 折叠;④ 设每 PR 评论上限。
- **webhook 入口**:Mac 在家做服务器需稳定公网入口(Cloudflare Tunnel),并注意 24h 续航/休眠设置。
- **AGPLv3**(Kodus):自用/内部无碍,若将来对外提供服务需注意开源义务。

---

## 8. 一句话结论

> **底座用 Kodus 自托管(最贴需求、最快落地),24h 脏活全压本地 Qwen-Coder(免费不限量),Semgrep/覆盖率等确定性工具先跑给硬证据降误报,订阅的 Codex/Claude 只通过官方 CLI 入口、对少数高价值 PR 做升级深审与汇总(严格限流防爆配额、且必须合规)。** 先按路径 A 一两天验证闭环,再视需要把"大脑分诊 + 多 worker 分维度"演进到自研 `Power-Reviewer`(路径 C)。全程只评论不改代码,风险最低。

---

## 参考来源

- [10 Open Source AI Code Review Tools Tested (2026) — Augment Code](https://www.augmentcode.com/tools/open-source-ai-code-review-tools-worth-trying)
- [PR-Agent (community-owned)](https://github.com/The-PR-Agent/pr-agent) · [Qodo: Changing a Model（Ollama/vLLM 配置）](https://qodo-merge-docs.qodo.ai/usage-guide/changing_a_model/) · [自托管 LiteLLM 讨论 #1645](https://github.com/qodo-ai/pr-agent/discussions/1645)
- [Kodus AI（自托管 AI code review）](https://github.com/kodustech/kodus-ai) · [Kodus self-hosted](https://kodus.io/self-hosted-ai-code-review/) · [Kodus CR CLI](https://github.com/kodustech/kodus-ai-cr)
- [Gito (Nayjest/Gito)](https://github.com/Nayjest/Gito) · [OpenReview (vercel-labs)](https://github.com/vercel-labs/openreview)
- [Best Local LLMs for Mac 2026 — InsiderLLM](https://insiderllm.com/guides/best-local-llms-mac-2026/) · [Best Qwen Models Ranked — InsiderLLM](https://insiderllm.com/guides/qwen-models-guide/) · [Best Local LLM Mac 64GB — BSWEN](https://docs.bswen.com/blog/2026-03-21-best-local-llm-mac-64gb/)
- [Qwen3-Coder (官方仓库)](https://github.com/QwenLM/Qwen3-Coder) · [Qwen3-Coder-Next（HF）](https://huggingface.co/Qwen/Qwen3-Coder-Next) · [Qwen3-Coder 官方博客](https://qwen.ai/blog?id=qwen3-coder)
- [Smart Orchestrator + Cheaper Sub-Agents — MindStudio](https://www.mindstudio.ai/blog/smart-orchestrator-cheaper-sub-agent-models-claude-code) · [The Code Agent Orchestra — Addy Osmani](https://addyosmani.com/blog/code-agent-orchestra/)
- [Semgrep + LLM 降误报 — Medium](https://medium.com/@adan.alvarez/diy-using-semgrep-with-llms-to-improve-code-reviews-d43d0584b34f) · [Semgrep AI-Powered Detection (IDOR)](https://semgrep.dev/blog/2025/ai-powered-detection-with-semgrep/) · [LLM 后置过滤静态分析误报（arXiv）](https://arxiv.org/pdf/2511.04023)
- [Claude Code Headless 自托管指南](https://amux.io/guides/claude-code-headless/) · [Max 计划 OAuth vs API Key（2026）](https://lalatenduswain.medium.com/claude-code-on-claude-max-plan-understanding-oauth-token-vs-api-key-authentication-in-2026-96a6213d2cde) · [误走 API 计费 $1800 事故 issue](https://github.com/anthropics/claude-code/issues/37686)
</content>
</invoke>
