#!/usr/bin/env bash
set -euo pipefail

IMAGE="crpi-qiclkwmeg0rcfork.cn-hangzhou.personal.cr.aliyuncs.com/dfctl/agent-env:latest"
VOLUMES_ROOT="$HOME/agent-volumes"
DEFAULT_PROXY="http://127.0.0.1:7890"

agent="claude"
username=""
proxy=""
persist=false
model=""
base_url=""
api_key=""
skills=""
repo=""
cmd=""

usage() {
  cat <<'HELP'
☁  空岛云 · AgentRun — 本地启动脚本

用法:
  ./scripts/run.sh [选项]

选项:
  -a AGENT       agent 类型: claude (默认) 或 codex
  -u NAME        用户名(默认随机 agent-xxxx)
  -x             启用宿主机代理(默认 127.0.0.1:7890)
  -X HOST:PORT   自定义代理地址
  -p             持久化(挂载 ~/agent-volumes/<用户名>/.claude)
  -b URL         API 端点(根据 -a 映射到对应环境变量)
  -m MODEL       模型 ID(根据 -a 映射到对应环境变量)
  -k KEY         API 密钥(根据 -a 映射到对应环境变量)
  -r REPO        Git 仓库地址,宿主机 clone 后挂载到 /workspace
  -s PATH        挂载自定义 skills 目录
  -c CMD         启动命令(默认: claude 或 codex,跟随 -a)
  -h             显示帮助

参数映射:
  -a claude  →  ANTHROPIC_API_KEY / ANTHROPIC_BASE_URL / ANTHROPIC_MODEL
  -a codex   →  OPENAI_API_KEY / OPENAI_BASE_URL / codex -m MODEL

示例:
  # Claude Code + 官方 API(需代理)
  ./scripts/run.sh -u alice -x -p

  # Claude Code + DeepSeek(国内直连)
  ./scripts/run.sh -u bob -p \
    -b https://api.deepseek.com/anthropic \
    -k sk-your-deepseek-key

  # Codex + DeepSeek(国内直连)
  ./scripts/run.sh -a codex -u bob -p \
    -b https://api.deepseek.com/v1 \
    -k sk-your-deepseek-key \
    -m deepseek-chat

  # Codex + OpenAI 官方(需代理)
  ./scripts/run.sh -a codex -u carol -x -p

  # Claude Code + OpenRouter
  ./scripts/run.sh -u dave -p \
    -b https://openrouter.ai/api/v1 \
    -k sk-or-your-key \
    -m anthropic/claude-sonnet-4

  # 指定 Git 仓库
  ./scripts/run.sh -u eve -x -p \
    -r https://github.com/user/repo.git

注意:
  同一个 DeepSeek key 可同时用于两个 agent,只是端点不同:
    Claude Code → https://api.deepseek.com/anthropic
    Codex       → https://api.deepseek.com/v1
HELP
  exit 0
}

while getopts "a:u:xX:pm:b:k:r:s:c:h" opt; do
  case $opt in
    a) agent="$OPTARG" ;;
    u) username="$OPTARG" ;;
    x) proxy="$DEFAULT_PROXY" ;;
    X) proxy="http://$OPTARG" ;;
    p) persist=true ;;
    m) model="$OPTARG" ;;
    b) base_url="$OPTARG" ;;
    k) api_key="$OPTARG" ;;
    r) repo="$OPTARG" ;;
    s) skills="$OPTARG" ;;
    c) cmd="$OPTARG" ;;
    h) usage ;;
    *) usage ;;
  esac
done

if [[ "$agent" != "claude" && "$agent" != "codex" ]]; then
  echo "错误: -a 只支持 claude 或 codex" >&2; exit 1
fi

if [[ -n "$base_url" && -z "$api_key" ]]; then
  echo "错误: 指定了 -b (API 端点) 但未指定 -k (API 密钥)" >&2; exit 1
fi

# 默认命令跟随 agent 类型
if [[ -z "$cmd" ]]; then
  if [[ -n "$api_key" ]]; then
    cmd="$agent"
  else
    cmd="bash"
  fi
fi

[[ -z "$username" ]] && username="agent-$(head -c4 /dev/urandom | xxd -p)"

# 如果指定了 repo,宿主机先 clone
repo_name=""
repo_mount=""
if [[ -n "$repo" ]]; then
  repo_name="$(basename "$repo" .git)"
  repo_dir="$VOLUMES_ROOT/$username/workspace/$repo_name"
  if [[ -d "$repo_dir/.git" ]]; then
    echo "仓库已存在,跳过 clone: $repo_dir"
  else
    echo "正在 clone: $repo → $repo_dir"
    mkdir -p "$(dirname "$repo_dir")"
    git clone "$repo" "$repo_dir"
  fi
  repo_mount="$repo_dir"
fi

args=(docker run -it --rm --network host --hostname "$username")

[[ -n "$proxy" ]] && args+=(-e "HTTPS_PROXY=$proxy" -e "HTTP_PROXY=$proxy")

# 根据 agent 类型映射环境变量
if [[ "$agent" == "claude" ]]; then
  [[ -n "$api_key" ]]  && args+=(-e "ANTHROPIC_API_KEY=$api_key")
  [[ -n "$base_url" ]] && args+=(-e "ANTHROPIC_BASE_URL=$base_url")
  [[ -n "$model" ]]    && args+=(-e "ANTHROPIC_MODEL=$model")
else
  [[ -n "$api_key" ]]  && args+=(-e "OPENAI_API_KEY=$api_key")
  [[ -n "$base_url" ]] && args+=(-e "OPENAI_BASE_URL=$base_url")
fi

if $persist; then
  vol_dir="$VOLUMES_ROOT/$username/.claude"
  mkdir -p "$vol_dir"
  args+=(-v "$vol_dir:/home/agent/.claude")
fi

if [[ -n "$repo_mount" ]]; then
  args+=(-v "$repo_mount:/workspace/$repo_name" -w "/workspace/$repo_name")
fi

if [[ -n "$skills" ]]; then
  skills="$(cd "$skills" && pwd)"
  args+=(-v "$skills:/home/agent/.claude/skills:ro")
fi

# codex 的 model 通过命令行 flag 传入
codex_model_flag=""
if [[ "$agent" == "codex" && -n "$model" && "$cmd" == "codex" ]]; then
  codex_model_flag="-m $model"
fi

C='\033[36m'; B='\033[1m'; D='\033[2m'; R='\033[0m'

echo ""
echo -e "  ${B}☁  AgentRun${R} ${D}· powered by 空岛云${R}"
echo -e "  ${D}──────────────────────────────────${R}"
echo -e "  ${C}agent${R}   $agent"
echo -e "  ${C}user${R}    $username"
[[ -n "$proxy" ]]      && echo -e "  ${C}proxy${R}   $proxy"
[[ -n "$base_url" ]]   && echo -e "  ${C}url${R}     $base_url"
[[ -n "$model" ]]      && echo -e "  ${C}model${R}   $model"
[[ -n "$api_key" ]]    && echo -e "  ${C}key${R}     ${api_key:0:8}..."
$persist               && echo -e "  ${C}volume${R}  ~/${vol_dir#$HOME/}"
[[ -n "$repo_mount" ]] && echo -e "  ${C}repo${R}    $repo_mount"
[[ -n "$skills" ]]     && echo -e "  ${C}skills${R}  $skills"
echo -e "  ${C}cmd${R}     $cmd $codex_model_flag"
echo -e "  ${D}──────────────────────────────────${R}"
echo ""

# 容器启动初始化
init='
# Claude Code: 创建 .claude.json 避免首次启动报错
if [ ! -f "$HOME/.claude.json" ]; then
  cat > "$HOME/.claude.json" <<CONF
{"autoUpdates":false,"hasCompletedOnboarding":true,"numStartups":1}
CONF
fi
'

exec "${args[@]}" "$IMAGE" bash -lic "$init exec $cmd $codex_model_flag"
