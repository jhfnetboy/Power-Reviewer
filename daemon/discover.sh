#!/usr/bin/env bash
# 发现层:用 gh search 镜像 prbot 的分类 + 枚举三个 org 的活跃仓,输出机读工作项(JSONL,一行一个)。
# 为什么轮询而非 webhook:你要 review 的很多是【别人 org 里的 PR】,你没有那些仓的 Actions 权限,
# 但 gh search 用你自己的身份在哪都能查。owned 仓可另配 Actions 降延迟(见 .github/workflows/)。
# 注:不用 set -e —— 代理(7890)偶发 reset,单个 gh 失败不该整脚本退出;改用每调用重试 3 次(同 prbot)。
set -uo pipefail
ORGS_CONF="${ORGS_CONF:-$HOME/.config/prbot/repos.conf}"

# gh 调用重试 3 次,全失败回退空 JSON(让下游 jq 不炸)
ghj(){ local i out; for i in 1 2 3; do out=$(gh "$@" 2>/dev/null) && { printf '%s' "$out"; return 0; }; sleep 2; done; printf '[]'; }
ghv(){ local i out; for i in 1 2 3; do out=$(gh "$@" 2>/dev/null) && { printf '%s' "$out"; return 0; }; sleep 2; done; printf ''; }

emit(){ # prio type repo [num] [sha]
  jq -cn --arg p "$1" --arg t "$2" --arg repo "$3" --arg num "${4:-}" --arg sha "${5:-}" \
    '{prio:$p,type:$t,repo:$repo,num:(($num|select(.!=""))|tonumber?),head:$sha}'
}
pr_sha(){ ghv pr view "$2" --repo "$1" --json headRefOid -q .headRefOid; }

# ── P0a:别人请我 review(最该处理)──
ghj search prs --review-requested=@me --state=open --json repository,number --limit 50 \
 | jq -r '.[] | "\(.repository.nameWithOwner)\t\(.number)"' \
 | while IFS=$'\t' read -r repo num; do emit P0 review_incoming "$repo" "$num" "$(pr_sha "$repo" "$num")"; done

# ── P0b:我自己的 open PR(被打回/更新都重审)──
ghj search prs --author=@me --state=open --json repository,number --limit 50 \
 | jq -r '.[] | "\(.repository.nameWithOwner)\t\(.number)"' \
 | while IFS=$'\t' read -r repo num; do emit P0 review_own "$repo" "$num" "$(pr_sha "$repo" "$num")"; done

# ── P2:三个 org 下活跃(非归档、近 90 天有 push)仓库 → 背景质量/文档巡检(长线、低优先)──
CUT="$(date -u -v-90d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '90 days ago' +%Y-%m-%dT%H:%M:%SZ)"
while read -r line; do
  case "$line" in ''|\#*) continue ;; esac
  if [[ "$line" == */* ]]; then
    emit P2 sweep "$line"
  else
    ghj repo list "$line" --limit 100 --no-archived --json nameWithOwner,pushedAt \
     | jq -r --arg cut "$CUT" '.[] | select(.pushedAt > $cut) | .nameWithOwner' \
     | while read -r repo; do emit P2 sweep "$repo"; done
  fi
done < "$ORGS_CONF"
