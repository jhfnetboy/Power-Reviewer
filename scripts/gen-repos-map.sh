#!/usr/bin/env bash
# 扫描你给的本地目录,按 git origin 自动配出【三个 org 的仓 → 本地路径】,生成 repos-local.map。
# 用法:  bash scripts/gen-repos-map.sh ~/Dev [更多目录...]   # 写入仓库根的 repos-local.map
set -uo pipefail
cd "$(dirname "$0")/.."
ORGS_CONF="${ORGS_CONF:-$HOME/.config/prbot/repos.conf}"
[ $# -ge 1 ] || { echo "用法: bash scripts/gen-repos-map.sh <本地目录> [更多目录...]"; exit 1; }

# 读 prbot 里的 org 名做过滤(只收这几个 org 的仓)
orgs="$(grep -vE '^\s*#|^\s*$' "$ORGS_CONF" 2>/dev/null | grep -v '/' | paste -sd'|' -)"
[ -z "$orgs" ] && orgs="AAStarCommunity|AuraAIHQ|MushroomDAO"

OUT=repos-local.map
: > "$OUT"
for base in "$@"; do
  base="${base/#\~/$HOME}"
  find "$base" -maxdepth 4 -name .git \( -type d -o -type f \) 2>/dev/null | while read -r g; do
    d="$(dirname "$g")"
    url="$(git -C "$d" remote get-url origin 2>/dev/null)" || continue
    slug="$(printf '%s' "$url" | sed -E 's#(git@github\.com:|https://github\.com/)##; s#\.git$##')"
    printf '%s' "$slug" | grep -qE "^($orgs)/" && printf '%s\t%s\n' "$slug" "$d" >> "$OUT"
  done
done
# 去重(同一 repo 多处 clone 只留第一个)
sort -u -k1,1 "$OUT" -o "$OUT" 2>/dev/null || true
echo "✅ 写好 $OUT,共 $(wc -l < "$OUT") 个仓:"
column -t "$OUT" 2>/dev/null | head -40
echo ""
echo "之后 run-opencode.sh / daemon(opencode 模式)就会用这些本地仓(worktree),不再重新 clone。"
