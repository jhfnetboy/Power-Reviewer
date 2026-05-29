#!/usr/bin/env bash
# 把本仓的 OpenCode 配置(agent/lens prompts/skill)同步到全局 ~/.config/opencode/,
# 这样 opencode 在【任何仓库目录】跑都能用上我们的 pr-reviewer(daemon 在临时 clone 里跑时需要)。
# 可重复执行(每次改了 opencode.json / prompts 后再跑一次)。首次会备份你原有全局配置。
set -euo pipefail
cd "$(dirname "$0")/.."
G="$HOME/.config/opencode"
mkdir -p "$G/prompts" "$G/skills"

# 1) 备份原有全局配置(仅首次)
if [ -f "$G/opencode.json" ] && [ ! -d "$G/_backup_session" ]; then
  mkdir -p "$G/_backup_session"
  cp "$G/opencode.json" "$G/_backup_session/" 2>/dev/null || true
fi

# 2) prompts:本仓自定义(security/docs)+ vendor 标准 lens(testing/consistency/design/solid/orchestrator)
cp prompts/pr-review-security.md prompts/pr-review-docs.md "$G/prompts/"
cp vendor/opencode-review/prompts/pr-reviewer-orchestrator.md \
   vendor/opencode-review/prompts/pr-review-testing.md \
   vendor/opencode-review/prompts/pr-review-consistency.md \
   vendor/opencode-review/prompts/pr-review-design.md \
   vendor/opencode-review/prompts/pr-review-solid.md "$G/prompts/"

# 3) gh-pr-review skill(opencode 发 inline review 用)
cp -R vendor/opencode-review/skills/gh-pr-review "$G/skills/"

# 4) opencode.json:把 {file:./vendor/opencode-review/prompts/...} 改成全局 {file:./prompts/...}
sed 's#\./vendor/opencode-review/prompts/#./prompts/#g' opencode.json > "$G/opencode.json"

python3 -m json.tool "$G/opencode.json" >/dev/null && echo "✅ 全局 opencode.json 合法"
echo "已同步到 $G:"
echo "  agent 模型: $(python3 -c "import json;print(json.load(open('$G/opencode.json'))['agent']['pr-reviewer']['model'])")"
echo "  prompts: $(ls "$G/prompts" | tr '\n' ' ')"
echo "  skill: gh-pr-review"
echo ""
echo "提醒:OMLX_API_KEY 需在跑 opencode 的环境里 export(opencode.json 里写的是 {env:OMLX_API_KEY})。"
