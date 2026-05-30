#!/usr/bin/env bash
# 一键把 opencode.json 里所有 agent 的模型切到某个后端,方便 benchmark。
# 用法:  scripts/switch-backend.sh <ollama|lmstudio|omlx|llamacpp>
# 还原:  git checkout opencode.json
set -euo pipefail
cd "$(dirname "$0")/.."

case "${1:-}" in
  ollama)   MODEL="ollama/qwen2.5-coder:32b" ;;
  lmstudio) MODEL="lmstudio/qwen2.5-coder-32b-instruct" ;;       # 改成 LM Studio 实际加载的模型名
  omlx)     MODEL="omlx/Qwen3-Coder-30B-A3B-Instruct-MLX-8bit" ;;                # 改成 omlx --model-dir 下的目录名/alias
  llamacpp) MODEL="llamacpp/default" ;;                          # 改成 llama-server 加载的模型名
  *) echo "用法: $0 <ollama|lmstudio|omlx|llamacpp>"; exit 1 ;;
esac

# 只替换 agent 定义里的 "model": "..."(provider 段用的是 "models" 复数 + 模型名做 key,不会被命中)
perl -0pi -e "s#\"model\":\s*\"[^\"]*\"#\"model\": \"$MODEL\"#g" opencode.json

echo "✅ 所有 agent 已切到: $MODEL"
echo "   benchmark 时统一用一个模型即可;想恢复 docs lens 用 8B 等差异化设置:git checkout opencode.json"
echo "   别忘了先把对应后端 server 起好、并加载同名模型。"
