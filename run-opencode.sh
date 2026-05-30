#!/usr/bin/env bash
# 产品② OpenCode agentic 深审:让 pr-reviewer 自主探索仓库(读文件/grep/git)再出多 lens 评审。
# 比直评慢(多 subagent × 多轮 tool-call),适合【重要 PR 按需深审】,不建议 24h 全量。
#
# 准备(首次或改了配置/模型后):  bash scripts/sync-opencode-global.sh
# 用法:
#   bash run-opencode.sh                  # 审当前仓当前分支(无 PR → 打印到 stdout)
#   bash run-opencode.sh owner/repo#123   # clone 该 PR 深审;DRY_RUN=1 只打印,否则发 inline 评论
set -euo pipefail
cd "$(dirname "$0")"
[ -f .env ] && { set -a; . ./.env; set +a; }
: "${OMLX_API_KEY:?请在 .env 里设 OMLX_API_KEY}"
export NO_PROXY="${NO_PROXY:-localhost,127.0.0.1}"
MODEL="${REVIEW_MODEL:-omlx/Qwen3-Coder-30B-A3B-Instruct-MLX-8bit}"
AGENT="${OPENCODE_AGENT:-pr-reviewer}"

TARGET="${1:-}"
if [ -z "$TARGET" ]; then
  echo "▶ OpenCode 深审【当前分支 vs main】(无 PR → stdout)  模型=$MODEL"
  exec opencode run --agent "$AGENT" -m "$MODEL" \
    "Review current branch against main. No PR number — print the review to stdout. Do not edit code."
fi

# 支持 owner/repo#N 或 完整 URL https://github.com/owner/repo/pull/N
if [[ "$TARGET" == *github.com/*/pull/* ]]; then
  repo="$(printf '%s' "$TARGET" | sed -E 's#.*github\.com/([^/]+/[^/]+)/pull/[0-9]+.*#\1#')"
  num="$(printf '%s'  "$TARGET" | sed -E 's#.*/pull/([0-9]+).*#\1#')"
else
  repo="${TARGET%%#*}"; num="${TARGET##*#}"
fi
[[ -n "$repo" && "$num" =~ ^[0-9]+$ ]] || { echo "❌ 解析不出 repo/PR:$TARGET"; exit 1; }
echo "  解析为: repo=$repo  pr=$num   DRY_RUN=${DRY_RUN:-0}"

# 优先用你的本地克隆(repos-local.map: "owner/repo  /abs/path");没有才回退 gh clone。
MAP="repos-local.map"
localdir=""
[ -f "$MAP" ] && localdir="$(awk -v r="$repo" '$1==r{print $2; exit}' "$MAP")"
localdir="${localdir/#\~/$HOME}"   # 展开 ~

if [ -n "$localdir" ] && [ -d "$localdir/.git" ]; then
  echo "▶ 用本地克隆 $localdir(git worktree,不走网络、不动你的工作分支)"
  git -C "$localdir" fetch -q origin "pull/$num/head:pr-review-$num" 2>/dev/null \
    || { echo "  fetch PR ref 失败(代理?)"; exit 1; }
  wt="$(mktemp -d)"
  trap 'git -C "$localdir" worktree remove --force "$wt" 2>/dev/null; rm -rf "$wt"' EXIT
  git -C "$localdir" worktree add -q --detach "$wt" "pr-review-$num"
  cd "$wt"
else
  echo "▶ ⚠️ repos-local.map 里没有 $repo → 回退 gh clone 到临时目录(慢/占盘)。建议加进 repos-local.map。"
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  gh repo clone "$repo" "$tmp" -- --depth 50 -q && cd "$tmp" && gh pr checkout "$num" -q || { echo "clone/checkout 失败"; exit 1; }
fi
if [ "${DRY_RUN:-0}" = "1" ]; then
  opencode run --agent "$AGENT" -m "$MODEL" \
    "Review the current branch against its base. No posting — print the review to stdout. Do not edit code."
else
  opencode run --agent "$AGENT" -m "$MODEL" \
    "Review PR #$num and post the synthesized inline review via the gh-pr-review skill. Do not edit code."
fi
