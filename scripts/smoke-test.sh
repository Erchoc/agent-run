#!/usr/bin/env bash
# smoke-test.sh <image> — 推送前的镜像冒烟测试
set -euo pipefail

IMG="${1:?用法: smoke-test.sh <image>}"

run() { docker run --rm "$IMG" "$@"; }

echo "==> 基础运行时"
run node --version
run python3 --version
run uv --version
run git --version
run rg --version | head -1

echo "==> Agent CLI"
run claude --version
run codex --version

echo "==> 非 root 确认"
[[ "$(run whoami)" == "agent" ]] || { echo "✗ 容器默认用户不是 agent"; exit 1; }

# 可选:真实 API 调用验证(需要 ANTHROPIC_API_KEY)
if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
  echo "==> Claude Code 真实调用"
  docker run --rm -e ANTHROPIC_API_KEY "$IMG" \
    claude -p "reply with exactly: SMOKE_OK" --max-turns 1 | grep -q "SMOKE_OK" \
    && echo " ✓ API 调用通过" \
    || { echo "✗ API 调用失败"; exit 1; }
else
  echo "==> 跳过真实 API 调用(未配置 ANTHROPIC_API_KEY)"
fi

echo "==> 冒烟测试全部通过 ✓"
