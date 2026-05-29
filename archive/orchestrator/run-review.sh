#!/usr/bin/env bash
# Power-Reviewer 自托管 runner 入口:本地模型 review →(必要时)升级大脑 → 发 PR 评论。
# 由 .github/workflows/review.yml 的 llm-review job 调用。
# 环境变量:PR_NUMBER REPO BASE_SHA HEAD_SHA GH_TOKEN LITELLM_BASE
set -euo pipefail

: "${PR_NUMBER:?}" "${REPO:?}" "${LITELLM_BASE:?}"
EVIDENCE_DIR="${EVIDENCE_DIR:-./.evidence}"
ESCALATE_DAILY_CAP="${ESCALATE_DAILY_CAP:-10}"   # 升级大脑每日硬上限,防爆订阅配额

echo "==> 1. 取 PR diff(只看改动,本地小模型省 token)"
DIFF="$(git diff "${BASE_SHA}...${HEAD_SHA}")"

# TODO(借鉴 PR-Agent §10.2):token-aware patch fitting。
#   大 PR 超本地模型上下文时,按文件/token 预算分块,逐块审后合并,别一坨塞进去。

echo "==> 2. 本地模型 review(在确定性证据基础上推理,降幻觉/降噪)"
# 方式 A(推荐起步):直接用 Kodus CR CLI,复用其 AST + 规则 + 评论格式。
#   TODO: 核对 vendor/kodus 内 kodus-ai-cr 的实际命令与参数(其文档有缺口,需读源码)。
#   预期形如:
#     ./vendor/kodus/cli review \
#        --provider openai --api-base "${LITELLM_BASE}" --model reviewer-local \
#        --evidence "${EVIDENCE_DIR}/semgrep.sarif" \
#        --rules ./kody-rules --format github
#
# 方式 B(自研):直接调 LiteLLM 端点,自己拼 prompt(prompt 即配置,见 prompts/)。
#   把 DIFF + 证据 + kody-rules 拼进 prompt,要求模型输出结构化 JSON:
#     [{ "file","line","severity":"Critical|High|Medium|Low","title","why","suggestion" }]
#   下面是方式 B 的占位骨架:
REVIEW_JSON="$(
  curl -sS "${LITELLM_BASE}/v1/chat/completions" \
    -H 'Content-Type: application/json' \
    -d "$(jq -n --arg diff "$DIFF" '{
      model: "reviewer-local",
      temperature: 0,
      messages: [
        {role:"system", content:"你是严格的代码审查器。只报高置信度问题,按 Critical/High/Medium/Low 分级。只输出 JSON 数组,不改代码。"},
        {role:"user", content:("审查以下 diff,结合 .evidence 下的 Semgrep 结果与 kody-rules 规则:\n\n" + $diff)}
      ]
    }')" | jq -r '.choices[0].message.content'
)" || { echo "本地模型调用失败 —— 按设计大声报错,不静默上云"; exit 1; }

echo "==> 3. 判定是否升级大脑(复杂/安全关键 PR)"
# 简单启发式:Critical/High 数量、是否命中安全规则、改动规模。命中且未超日配额才升级。
# 升级【只走官方 CLI】(合规):
#   claude -p "深审这个 PR 的安全与业务一致性:..."   # 走 Claude Code Max 订阅
#   codex exec "..."                                  # 走 Codex Pro
# TODO: 实现 escalate 判定 + 日配额计数(防爆,见 §1 约束二)。

echo "==> 4. 发回 PR 评论(分级、可折叠、设每 PR 上限以降噪)"
# 用 gh 发 review 评论。占位:把 REVIEW_JSON 渲染成 markdown 后发布。
# TODO: 逐条 inline 评论(gh api .../comments)或一条汇总 review(gh pr review)。
echo "$REVIEW_JSON" | jq '.' >/dev/null 2>&1 && echo "（review JSON 就绪,待接入 gh 发布逻辑）" || echo "（模型未返回合法 JSON,需加 self-reflection 重试,见 §10.3）"

echo "==> done."
