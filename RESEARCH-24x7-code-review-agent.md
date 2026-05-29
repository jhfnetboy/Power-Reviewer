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

## 9. Kodus 深入(已弃用,概念保留于此节)

> 状态:Kodus 代码已从仓库移除(重型 NestJS 平台,不符合轻量取向)。本节作为"借鉴存档"保留——其 AST 上下文、KodyRules、去重思路的实现已由 OpenCode 多 lens(§17)覆盖。

**定位**:开源(AGPLv3)、可完全自托管的 AI code review 引擎,哲学是 **"AST 确定性分析 + LLM 语义分析 + 自定义规则 = 低噪声"**——正好对上"24h 跑但别刷屏"的核心痛点。

**review 流水线(webhook 进来之后)**:
```
GitHub webhook → ① 起 sandbox(默认 local 跑在 worker;或付费 e2b 远程)
→ ② 构建 AST 图(确定性,非 GPT)读模块依赖
→ ③ 从工具拉上下文(插件:Jira / CI 日志 / 测试覆盖率)
→ ④ 多个专门 agent 并行 review(KodyRulesAgent + 安全/质量…)
→ ⑤ 去重 + 按严重度分级 + 给修改建议
→ ⑥ 发回 PR 评论
```
全程在自己网络/数据库/基础设施里跑,代码不出网。

**组件(Docker 全栈)**:`web` + `api` + `worker` + `webhooks`(独立服务,3332 端口)+ `RabbitMQ` + `Postgres/pgvector` + `MongoDB`。

**对本项目特别有用的亮点**:
- **KodyRules / Policy-as-Code**:用大白话写规则、可**按文件夹**生效("此目录必须有测试""API 改动必须更新文档")。七项诉求里"文档同步/测试完整/业务一致性"很多可直接编码成规则,不靠模型瞎猜。
- **自动识别已有规则文件**:能读 Cursor / Copilot / Claude / Windsurf 的 rule 文件。
- **模型无关**:任意 OpenAI 兼容端点 → 直指本地 Ollama/LiteLLM。
- **AST 规则引擎给 LLM 喂"精确结构化上下文"**而非整坨 diff,这是降噪的根。
- 默认只评论不改代码,符合 review-only 诉求。
- 有 CLI 版 **`kodus-ai-cr`**,适合塞进 CI(见 §11)。

**老实说的 caveat**:
1. **跨文件能力营销 vs 实测有落差**:官方主打"AST 图 + 跨文件上下文",但独立的 450K 文件 monorepo 评测发现它实际仍偏"单文件孤立审查",跨服务破坏性改动捕捉不如预期。"业务一致性"别指望开箱即用,要靠 KodyRules + pgvector 检索补。
2. **文档有缺口、星不多(~976★)**:多语言 monorepo 配置文档不全,部分要读源码;非 TS 项目生产效果未充分验证。

## 10. PR-Agent 可借鉴清单(B 方案不采用,但抄设计)

无论最后走 Kodus 还是自研,这些模式都值得抄:
1. **⭐ "Prompt 即配置,而非代码"**:检查类别/严重度阈值/规则放在 JSON/TOML + prompt 模板里,改行为不改代码、不重新部署。自研一开始就这么设计,迭代快一个量级。
2. **⭐ Adaptive token-aware patch fitting**:大 PR 装不下窗口时,按 token 预算自适应压缩/分块且保住语义。**本地小模型上下文窗口比云小**,这套策略几乎一定用得上。
3. **单工具单次 LLM 调用 + self-reflection 自校验**:`/review` 等单次调用(~30s)换速度/成本,加自检步骤降幻觉。24h 追求吞吐时比多轮 agent 划算。
4. **Provider/平台抽象层**:LLM provider 和 Git 平台都抽象掉 → 对应到用 LiteLLM 做统一端点。
5. **⚠️ 两个反面教材(主动规避)**:
   - **静默回退云端**:本地配置有 bug 时(issues #2098/#2083)会悄悄 fallback 到 OpenAI——对"代码不出网"是灾难。**教训:本地优先要显式、失败要大声报错,绝不静默上云。**
   - **localhost 可达性**:不能用 GitHub 托管 runner 连本机 Ollama。**教训:本地模型的 review 执行必须跑在能访问本地模型的机器上(那台 Mac)。**

## 11. 利用 GitHub 免费算力(重要架构优化)

**核心事实(2026)**:
- **公开仓库**:GitHub Actions 标准托管 runner **完全免费**;**自托管 runner 也免费**;**CodeQL 代码扫描免费**。
- **私有仓库**:托管 runner 有按 plan 的免费分钟配额;CodeQL 需 **GHAS(付费)**;自托管 runner 原计划 2026-03 起 $0.002/min(已推迟、重新评估中)。

**⭐ 关键洞察:把 GitHub Actions 当"编排 + webhook + 确定性算力"层,把那台 Mac 注册成 self-hosted runner 跑本地模型。** 这样:
- **省掉自建 webhook/隧道**:Actions 原生就是触发器,不必为触发去搭 Kodus 的 RabbitMQ/Postgres 全栈,也不必 Cloudflare Tunnel。
- **解决 localhost 可达性**(§10 的坑):本地模型 job 直接派发到你 Mac 上的 self-hosted runner。
- **确定性层白嫖免费托管 runner**:Semgrep / CodeQL(公开仓库)/ lint / 测试 / 覆盖率 diff 跑在免费 GitHub 托管 runner 上;只有"本地 LLM review"这一步派给 Mac。

**因此推荐的混合编排**:
```
GitHub Actions (PR 触发, 免费)
├─ job A (github-hosted, 免费): Semgrep + CodeQL(公开仓) + lint + test + coverage diff
│        └─ 把硬证据(SARIF/覆盖率)作为 artifact 传给 job B
└─ job B (self-hosted = 你的 Mac): 本地 Qwen-Coder 在硬证据基础上做语义 review
         └─ 复杂/安全关键时,经官方 CLI 升级到订阅大脑(限流)
         └─ gh pr comment / review API 发回评论
```
- **建议主力仓库尽量用公开仓**(若可能):Actions + 自托管 runner + CodeQL 全免费。
- **私有仓库**:用 Semgrep OSS 替代 CodeQL(免费、自托管),自托管 runner 计费变动留意官方最新口径。
- 可直接在 job B 里跑 **`kodus-ai-cr` CLI**,省掉 Kodus 整套 Docker 栈。

## 12. Fork 策略与仓库结构(待定,见正文问题)

现状:`Power-Reviewer` 已是 git 仓库,`origin = github.com/jhfnetboy/Power-Reviewer`。
诉求:fork Kodus 作为上游,在其上加自己的 feature;Power-Reviewer 同时保留自己的 origin。

三种结构(详见对话):
- **结构①(推荐)两仓 + submodule**:Power-Reviewer 当"大脑/编排 + Actions + 自定义 feature";另 fork Kodus 为独立仓(`upstream=kodustech/kodus-ai`),以 submodule 挂进 `vendor/kodus`。升级上游干净,AGPL 边界清晰,feature 不与 Kodus monorepo 纠缠。
- **结构② 单仓即 Kodus fork**:Power-Reviewer 本身 = Kodus fork(`origin=自己`,`upstream=Kodus`,`merge --allow-unrelated-histories`)。可深度改 Kodus 内部,但合并维护痛、AGPL 覆盖整库。
- **结构③ 多 remote 仅参考**:`origin` + `upstream-kodus` + `upstream-pragent` 只读,cherry-pick/参考,不整树合并。最轻,适合"借鉴为主"。

> ⚠️ 阻塞项:`gh` 当前 token 失效 + 代理(127.0.0.1:7890)connection reset,需先 `gh auth login` 才能真正在 GitHub fork。

---

## 13. 本地模型能力边界(27B dense vs MoE)与典型场景

**架构定调**:不运行 Kodus 重型平台,改用轻量自研 agent(Flask+RQ+LangGraph+Ollama),Kodus 降为参考源。理由:省资源、全控制,契合"本地免费 token 24h 跑"的取向。`vendor/kodus` 留作借鉴(AST 上下文、KodyRules 格式、去重)。

### 27B dense(Qwen2.5-Coder-32B)启动后的典型场景(按擅长度排序)
上下文有限 → 只做**边界清晰、局部**的任务:
1. **Diff 级 review**(PR 改动本身,天然有界)—— 主力场景
2. **单文件安全模式扫描**(注入、硬编码密钥、危险 API);Web3 项目配合 Slither/Semgrep 给硬证据
3. **文档/注释同步检查**(签名改了文档没改)—— 可派给 8B 并行
4. **测试完备性**(改了代码有没有配套测试)—— 配合覆盖率 diff
5. **明显 bug / 代码异味 / lint 级问题**
6. **commit message / PR 描述质量**

❌ **放弃业务一致性**:需跨文件/全仓上下文,超 27B 窗口能力,交给升级大脑。

### 切 MoE(如 Qwen3-Coder-30B-A3B)能力会涨吗?
- **主要收益是速度/吞吐**(3B 激活),**不等于上下文变大**。质量同档,审得更快、24h 能审更多 PR。
- **能力范围扩展的真正来源是"上下文长度 + 推理力",不是 MoE 本身**:
  - 换**长上下文模型**(或 Qwen3-Coder-Next 80B-A3B)→ 才谈得上跨文件/多文件推理 → 业务一致性才部分可行
  - 否则跨文件/决策性的活,仍应**升级到 Claude/Codex**
- 结论:MoE 让你"更快更多",长上下文/云端大脑才让你"更深"。别指望换 MoE 就解锁业务一致性。

## 14. litebox 不适用(已查证)

[microsoft/litebox](https://github.com/microsoft/litebox) 是 **Rust 写的安全沙箱 library OS**(跑单个进程、收窄host接口),**不是容器/镜像运行时**,无法运行 Kodus 的多服务 docker-compose 栈;且尚在早期、API 不稳。
- **真正的省资源做法不是 litebox,而是根本不跑 Kodus 平台**——用轻量自研 agent(纯 Python+Ollama,顶多加个 Redis),无需 Docker。
- 沙箱隔离当前不需要:Semgrep/CodeQL 不执行代码,self-hosted runner/本机已够隔离。将来若要在 review 中执行不可信代码,再评估 litebox/e2b。

## 15. 升级/决策的最佳实践:GitHub PR 作为人机媒介(强烈推荐)

两种把"大上下文/决策"接进来的方式:
- **(A) 工具内置自动调用 Claude/Codex**:ToS 灰色(订阅被自动化调用)、烧周配额、难审计。**仅作罕见、限流的升级用**,且必须走官方 CLI。
- **(B) ⭐ GitHub PR 作为媒介(推荐默认)**:本地 bot 把发现作为 PR 评论/review 贴出;**你在 Claude Code/Codex 里交互式打开 PR、读评论、对存疑项深挖与决策**。异步、可审计、人在环、**完全合规**(你本人交互式使用订阅)、不烧自动化配额、留存记录。

**完整 PR 生命周期(最佳实践)**:
```
1. 你/同事开 PR
2. [免费 GitHub Actions] Semgrep/CodeQL/test/coverage → 硬证据(SARIF)
3. [本地 24h bot] Qwen 在硬证据上 review → 结构化评论贴回 PR,分级
      - 局部问题(安全/文档/测试/bug):直接给可操作建议
      - 跨文件/业务/决策性:标 `needs-human-brain` 标签,只提问不下结论
4. [你,按自己节奏] 在 Claude Code / Codex 打开 PR:
      - 扫一遍 bot 的分级评论(秒级决定 merge / 改 / 忽略)
      - 对 `needs-human-brain` 项,用 Claude/Codex 交互式深挖 + 决定 + 让它改
5. merge
```
要点:**bot 做分诊(triage),你+大模型做判断(judgment)**——这是 2026 主流的人机分工。可选中间档:对极少数高价值 PR,本地 bot 经官方 `claude -p` 自动升级,但设日配额硬上限(见 §1)。

## 16. 两种能力:被动 PR review + 主动代码库扫描

不止跟踪已有 PR,还要能**主动扫描代码库**给质量/安全/性能评估:
- **被动(事件驱动)**:webhook,PR 来了就审(本仓 `agent/`)。
- **主动(定时扫描)**:`on: schedule`(GitHub Actions cron)或本地 cron,定期对全仓/指定目录跑一遍,产出报告或开 issue。无需手动维护 clone(Actions 自动签出;本地扫描则指向已 clone 目录)。

---

## 17. 底座决策:OpenCode + 多 lens(路线乙,已采纳)

调研轻量可 fork 方案后(PR-Agent / shin-pr-review-agent / agentuse / Gito / OpenCode),采纳 **OpenCode + opencode-review 多 lens 编排**:

- **为什么不从零写**:`agent/`(Flask+RQ+LangGraph)能跑但不成熟;站在成熟工具上更省力。已归档到 `archive/flask-agent/` 作 fallback。
- **为什么不是 PR-Agent(B)**:Qodo 已弃为 legacy;本地模型有静默回退 OpenAI 的 bug(#2098/#2083 4+月未修),对"代码不出网"致命。
- **为什么 OpenCode**:provider-agnostic agent 运行时(类 Claude Code),**同一工具本地跑 24h、切订阅做深审**;`opencode-review` 已实现 orchestrator + 5 lens 并行 fan-out + 结构化 JSON + 自动 inline 评论(连行号校验/422 恢复都做好);可跑在 GitHub runner(免费算力)。

**本仓适配**(`opencode.json`):
- provider 改 **ollama 本地**(`@ai-sdk/openai-compatible` → `localhost:11434/v1`),模型 Qwen2.5-Coder-32B / Qwen3-8B。
- lens:security(**OWASP + Web3/Paymaster/EIP-7702 专项**,本仓自定义)、testing、**docs(本仓自加,补第7项诉求)**、consistency 默认启用;design/solid 默认关(本地 27B 较吃力 + 串行慢),留升级深审。
- 本地并发=1(`OLLAMA_NUM_PARALLEL=1`),orchestrator 并行 fan-out 实际在 Ollama 排队,避免 OOM。
- `vendor/opencode-review` 作参考 submodule:复用标准 lens prompts 与 gh-pr-review skill;无 LICENSE,故不拷贝进本仓,运行时按路径引用。

**升级深审仍走 PR-as-medium(§15)**,不在配置里自动调订阅。

---

## 18. 本地推理后端(Mac):Ollama vs MLX,benchmark 顺序

**Ollama 底层(2026)**:Apple Silicon 自 **0.19(2026-03)起换 MLX**(preview,llama.cpp 的 Metal 后端退役),但 **MLX 加速覆盖的模型仍有限**,未覆盖的回退 ggml/llama.cpp;Linux/Windows 仍 llama.cpp。
**实测梯度**(M4 Pro, Qwen3-Coder-30B-A3B):MLX ~130 tok/s > 原生 llama.cpp Metal ~89 > 旧 Ollama(llama.cpp 后端)~43。⇒ "llama.cpp 比 Ollama 快"的旧建议对**新版 Ollama(MLX)部分失效**。

**四个候选(都 OpenAI 兼容,`opencode.json` 已配,`scripts/switch-backend.sh` 切)**:
- **Ollama**:最省心;受 `NUM_PARALLEL=1` 约束 → 多 lens 串行。
- **LM Studio**:MLX + GUI + 模型管理(端口 1234)。
- **oMLX**([jundot/omlx](https://github.com/jundot/omlx),Apache-2.0,**最看好**):MLX/mlx-lm + **连续批处理**(多 lens 真并行,无需 NUM_PARALLEL=1)+ **内置 tool-call 解析** + 分层 KV 缓存(prefix 复用,专为 Claude Code 类 agent 优化)+ 进程内存上限/LRU/brew services 自动重启(比 Ollama 的 Jetsam LaunchAgent + 串行更优雅)+ OpenCode 一键集成 + 多模型同serving。
- **llama.cpp `llama-server`**:原生 Metal,最大控制(端口 8080)。

**决策规则**:OpenCode 是 agentic,**tool-call 可靠性 > 最后 15% tok/s**。先 Ollama 跑通 → LM Studio → oMLX,在同一真实 PR 比 tok/s + tool-call 成功率。oMLX 因连续批处理 + 原生 tool-call,理论上对"多 lens 并行 + agentic"最契合。

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
- [Kodus Policy-as-Code Review](https://kodus.io/policy-as-code-review/) · [Show HN: Kodus（AST + LLM, less noise）](https://news.ycombinator.com/item?id=43572816) · [Kodus CR CLI](https://github.com/kodustech/kodus-ai-cr)
- [GitHub Actions Billing & Usage](https://docs.github.com/en/actions/concepts/billing-and-usage) · [Actions 定价变更（2026）](https://resources.github.com/actions/2026-pricing-changes-for-github-actions/) · [自托管 runner 计费推迟](https://devclass.com/2025/12/17/github-to-charge-for-self-hosted-runners-from-march-2026/)
- [About GitHub Advanced Security（CodeQL 私有仓需 GHAS）](https://docs.github.com/en/get-started/learning-about-github/about-github-advanced-security) · [About code scanning with CodeQL](https://docs.github.com/en/code-security/code-scanning/introduction-to-code-scanning/about-code-scanning-with-codeql)
- [OpenCode GitHub PR Review 文档](https://opencode.ai/docs/github/) · [OpenCode Providers（本地/兼容端点）](https://opencode.ai/docs/providers/) · [OpenCode + Ollama（官方集成）](https://docs.ollama.com/integrations/opencode)
- [cedricwider/opencode-review（多 lens 编排底座）](https://github.com/cedricwider/opencode-review) · [BerriAI/shin-pr-review-agent](https://github.com/BerriAI/shin-pr-review-agent) · [agentuse/pr-review-agent](https://github.com/agentuse/pr-review-agent) · [Nayjest/Gito](https://github.com/Nayjest/Gito)
- [Using OpenCode in CI/CD for AI PR reviews — Martin Alderson](https://martinalderson.com/posts/using-opencode-in-cicd-for-ai-pull-request-reviews/) · [microsoft/litebox](https://github.com/microsoft/litebox)
- [Ollama is now powered by MLX on Apple Silicon](https://ollama.com/blog/mlx) · [MLX vs Ollama vs llama.cpp 2026 benchmarks](https://willitrunai.com/blog/mlx-vs-ollama-apple-silicon-benchmarks) · [jundot/oMLX(MLX 推理 + 连续批处理 + 分层KV缓存)](https://github.com/jundot/omlx)
</content>
</invoke>
