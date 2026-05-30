#!/usr/bin/env bash
# 在这台 Mac(self-hosted runner)上装齐 OpenCode 多维度审查。
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> 0. 子模块(opencode-review 参考 + kodus)"
git submodule update --init --recursive

echo "==> 1. OpenCode CLI"
command -v opencode >/dev/null 2>&1 || {
  echo "请先装 OpenCode:  brew install anomalyco/tap/opencode   (或见 https://opencode.ai)"; exit 1; }

echo "==> 2. Ollama + 模型(主力 dense 先跑通)"
command -v ollama >/dev/null 2>&1 || { echo "请先装 ollama:  brew install ollama"; exit 1; }
ollama pull qwen2.5-coder:32b
ollama pull qwen3:8b

echo "==> 3. 让 Ollama 常驻(坑#3/#6:Jetsam 自重启 + 串行)"
cp deploy/com.power-reviewer.ollama.plist ~/Library/LaunchAgents/
launchctl unload ~/Library/LaunchAgents/com.power-reviewer.ollama.plist 2>/dev/null || true
launchctl load -w ~/Library/LaunchAgents/com.power-reviewer.ollama.plist

cat <<'EOF'

✅ 准备就绪。
- opencode.json 在仓库根,已配 ollama 本地 provider + 多 lens(security/testing/docs/consistency)。
- 本地试跑(在某个 git 仓内):  opencode run --agent pr-reviewer "Review current branch against main. PR #<n>."
- 接 GitHub:把 .github/workflows/{deterministic,opencode}.yml 放进被审查仓,
  并按 scripts/register-runner.md 把本机注册成带 power-reviewer 标签的 self-hosted runner。

注意(坑#1/#7):
- brew pin ollama 锁版本,避免自动更新引入 M 系 GPU 降级 bug。
- 确认 NO_PROXY=localhost,127.0.0.1,否则 Clash(7890)吞掉本地 11434 请求。
- 若 OpenCode 工具调用不稳,把 Ollama num_ctx 提到 16k-32k。
EOF
