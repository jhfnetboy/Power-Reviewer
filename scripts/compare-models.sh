#!/usr/bin/env bash
# A/B 对比不同模型的直评效果(同一 diff / PR,顺序跑,看 findings + 耗时)。
# 用法:
#   scripts/compare-models.sh <owner/repo#PR> [模型1 模型2 …]
#   scripts/compare-models.sh <some.diff>     [模型1 模型2 …]
# 不给模型则用下面两个默认对比。
set -uo pipefail
cd "$(dirname "$0")/.."
[ -f .env ] && { set -a; . ./.env; set +a; }

TARGET="${1:?需要 owner/repo#PR 或 diff 文件路径}"; shift || true
MODELS=("$@")
[ ${#MODELS[@]} -eq 0 ] && MODELS=(
  "omlx/Qwen3-Coder-30B-A3B-Instruct-MLX-8bit"
  "${NEXT_MODEL:-omlx/Qwen3-Coder-Next-4bit}"
)

if [[ "$TARGET" == *"#"* ]]; then
  SRC=(--repo "${TARGET%%#*}" --pr "${TARGET##*#}")
else
  SRC=(--diff-file "$TARGET")
fi

for m in "${MODELS[@]}"; do
  echo "============================================================"
  echo "模型: $m"
  echo "============================================================"
  start=$SECONDS
  python3 review/direct_review.py "${SRC[@]}" --model "$m" \
    --lenses "${REVIEW_LENSES:-security,testing,docs,consistency}" --dry-run 2>&1 | tail -30
  echo "  ⏱ 耗时: $((SECONDS - start))s"
  echo ""
done
echo "提示:omlx 会按 LRU 在两个模型间换页,首个请求触发加载会慢,属正常。"
