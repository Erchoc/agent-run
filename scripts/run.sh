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
repo=""
cmd="bash"

usage() {
  cat <<'HELP'
☁  空岛云 · AgentRun — 本地启动脚本

用法:
  ./scripts/run.sh [选项]

选项:
  -u NAME        用户名(默认随机 agent-xxxx,也用作持久化目录名)
  -x             启用宿主机代理(默认 127.0.0.1:7890)
  -X HOST:PORT   自定义代理地址
  -p             持久化(挂载 ~/agent-volumes/<用户名>/.claude)
  -b URL         API 端点(ANTHROPIC_BASE_URL)
  -m MODEL       模型 ID(ANTHROPIC_MODEL)
  -k KEY         API 密钥(ANTHROPIC_API_KEY)
  -r REPO        Git 仓库地址,启动后自动 clone 到 /workspace
  -s PATH        挂载自定义 skills 目录
  -c CMD         启动命令(默认 bash)
  -h             显示帮助

示例:
  # 最简启动(随机用户名,无代理,无持久化)
  ./scripts/run.sh

  # 官方 API + 代理 + 持久化(订阅账号,容器内 /login 登录)
  ./scripts/run.sh -u alice -x -p

  # 通过 OpenRouter 使用 Claude(国内直连,不需要代理)
  ./scripts/run.sh -u bob -p \
    -b https://openrouter.ai/api/v1 \
    -k sk-or-your-key \
    -m anthropic/claude-sonnet-4

  # 指定 Git 仓库(公网 GitHub,需代理)
  ./scripts/run.sh -u carol -x -p \
    -r https://github.com/user/repo.git

  # 指定 Git 仓库(内网 GitLab,免代理)
  ./scripts/run.sh -u dave -p \
    -r https://code.alibaba-inc.com/group/repo.git

  # 自定义 skills + 启动命令
  ./scripts/run.sh -u eve -x -p -s ~/my-skills -c "claude -p 'hello'"

注意:
  Claude Code 只能使用 Claude 系列模型,不支持 DeepSeek / GPT 等。
  -b 用于指定第三方 Claude 代理网关(如 OpenRouter),不是替换模型。
  容器内的 Codex 可独立使用 OpenAI 系模型(通过 config.toml 配置)。
HELP
  exit 0
}

while getopts "u:xX:pm:b:k:r:s:c:h" opt; do
  case $opt in
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

if [[ -n "$base_url" && -z "$api_key" ]]; then
  echo "错误: 指定了 -b (API 端点) 但未指定 -k (API 密钥)" >&2
  exit 1
fi

[[ -z "$username" ]] && username="agent-$(head -c4 /dev/urandom | xxd -p)"

# 如果指定了 repo,宿主机先 clone,然后挂载进容器
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

[[ -n "$proxy" ]]    && args+=(-e "HTTPS_PROXY=$proxy" -e "HTTP_PROXY=$proxy")
[[ -n "$api_key" ]]  && args+=(-e "ANTHROPIC_API_KEY=$api_key")
[[ -n "$base_url" ]] && args+=(-e "ANTHROPIC_BASE_URL=$base_url")
[[ -n "$model" ]]    && args+=(-e "ANTHROPIC_MODEL=$model")

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

C='\033[36m'; B='\033[1m'; D='\033[2m'; R='\033[0m'

echo ""
echo -e "  ${B}☁  AgentRun${R} ${D}· powered by 空岛云${R}"
echo -e "  ${D}──────────────────────────────────${R}"
echo -e "  ${C}user${R}    $username"
[[ -n "$proxy" ]]      && echo -e "  ${C}proxy${R}   $proxy"
[[ -n "$base_url" ]]   && echo -e "  ${C}url${R}     $base_url"
[[ -n "$model" ]]      && echo -e "  ${C}model${R}   $model"
[[ -n "$api_key" ]]    && echo -e "  ${C}key${R}     ${api_key:0:8}..."
$persist               && echo -e "  ${C}volume${R}  ~/${vol_dir#$HOME/}"
[[ -n "$repo_mount" ]] && echo -e "  ${C}repo${R}    $repo_mount → /workspace/$repo_name"
[[ -n "$skills" ]]     && echo -e "  ${C}skills${R}  $skills"
echo -e "  ${C}cmd${R}     $cmd"
echo -e "  ${D}──────────────────────────────────${R}"
echo ""

exec "${args[@]}" "$IMAGE" $cmd
