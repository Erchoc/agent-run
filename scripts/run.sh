#!/usr/bin/env bash
set -euo pipefail

IMAGE="crpi-qiclkwmeg0rcfork.cn-hangzhou.personal.cr.aliyuncs.com/dfctl/agent-env:latest"
VOLUMES_ROOT="$HOME/agent-volumes"
DEFAULT_PROXY="http://127.0.0.1:7890"

username=""
proxy=""
persist=false
model=""
base_url=""
api_key=""
skills=""
cmd="bash"

usage() {
  cat <<'HELP'
agent-env 本地启动脚本

用法:
  ./scripts/run.sh [选项]

选项:
  -u NAME        用户名(默认随机 agent-xxxx,也用作持久化目录名)
  -x             启用宿主机代理(默认 127.0.0.1:7890)
  -X HOST:PORT   自定义代理地址
  -p             持久化(挂载 ~/agent-volumes/<用户名>/.claude)
  -b URL         API 端点(ANTHROPIC_BASE_URL,第三方兼容服务必填)
  -m MODEL       模型 ID(ANTHROPIC_MODEL)
  -k KEY         API 密钥(ANTHROPIC_API_KEY,第三方兼容服务必填)
  -s PATH        挂载自定义 skills 目录
  -c CMD         启动命令(默认 bash)
  -h             显示帮助

示例:
  # 最简启动(随机用户名,无代理,无持久化)
  ./scripts/run.sh

  # 官方 API + 代理 + 持久化(订阅账号,容器内 /login 登录)
  ./scripts/run.sh -u alice -x -p

  # DeepSeek 替代(需要 base_url + api_key + model)
  ./scripts/run.sh -u bob -p \
    -b https://api.deepseek.com/v1 \
    -k sk-your-deepseek-key \
    -m deepseek-chat

  # OpenRouter 替代
  ./scripts/run.sh -u carol -p \
    -b https://openrouter.ai/api/v1 \
    -k sk-or-your-key \
    -m anthropic/claude-sonnet-4

  # 自定义 skills + 启动命令
  ./scripts/run.sh -u dave -x -p -s ~/my-skills -c "claude -p 'hello'"

第三方服务说明:
  使用 DeepSeek / OpenRouter / 自建网关等非官方 API 时,
  必须同时指定 -b (端点) 和 -k (密钥),可选 -m (模型)。
  此时不需要 -x 代理(第三方服务国内直连)。
HELP
  exit 0
}

while getopts "u:xX:pm:b:k:s:c:h" opt; do
  case $opt in
    u) username="$OPTARG" ;;
    x) proxy="$DEFAULT_PROXY" ;;
    X) proxy="http://$OPTARG" ;;
    p) persist=true ;;
    m) model="$OPTARG" ;;
    b) base_url="$OPTARG" ;;
    k) api_key="$OPTARG" ;;
    s) skills="$OPTARG" ;;
    c) cmd="$OPTARG" ;;
    h) usage ;;
    *) usage ;;
  esac
done

if [[ -n "$base_url" && -z "$api_key" ]]; then
  echo "错误: 指定了 -b (API 端点) 但未指定 -k (API 密钥)" >&2
  exit 1
fi

[[ -z "$username" ]] && username="agent-$(head -c4 /dev/urandom | xxd -p)"

args=(docker run -it --rm --network host --hostname "$username")

[[ -n "$proxy" ]]    && args+=(-e "HTTPS_PROXY=$proxy" -e "HTTP_PROXY=$proxy")
[[ -n "$api_key" ]]  && args+=(-e "ANTHROPIC_API_KEY=$api_key")
[[ -n "$base_url" ]] && args+=(-e "ANTHROPIC_BASE_URL=$base_url")
[[ -n "$model" ]]    && args+=(-e "ANTHROPIC_MODEL=$model")

if $persist; then
  vol_dir="$VOLUMES_ROOT/$username/.claude"
  mkdir -p "$vol_dir"
  args+=(-v "$vol_dir:/home/agent/.claude")
fi

if [[ -n "$skills" ]]; then
  skills="$(cd "$skills" && pwd)"
  args+=(-v "$skills:/home/agent/.claude/skills:ro")
fi

echo "┌─ agent-env ─────────────────────────"
echo "│ 用户:   $username"
[[ -n "$proxy" ]]    && echo "│ 代理:   $proxy"
[[ -n "$base_url" ]] && echo "│ 端点:   $base_url"
[[ -n "$model" ]]    && echo "│ 模型:   $model"
[[ -n "$api_key" ]]  && echo "│ 密钥:   ${api_key:0:8}..."
$persist             && echo "│ 持久化: $VOLUMES_ROOT/$username/.claude"
[[ -n "$skills" ]]   && echo "│ Skills: $skills"
echo "│ 命令:   $cmd"
echo "└──────────────────────────────────────"

exec "${args[@]}" $cmd
