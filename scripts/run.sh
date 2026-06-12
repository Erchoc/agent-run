#!/usr/bin/env bash
# run.sh — agent-env 本地启动脚本
# 用法:
#   ./scripts/run.sh                          # 最简启动(随机用户名,无代理,无持久化)
#   ./scripts/run.sh -u alice -p -x           # 自定义用户名 + 持久化 + 代理
#   ./scripts/run.sh -u bob -m claude-sonnet-4-6 -s ~/my-skills -c "claude -p hello"
#
# 选项:
#   -u NAME     用户名(默认随机 agent-xxxx)
#   -x          启用宿主机代理(127.0.0.1:7890)
#   -X HOST:PORT  自定义代理地址
#   -p          启用持久化(挂载 ~/.claude 到 ~/agent-volumes/<name>/.claude)
#   -m MODEL    设置 ANTHROPIC_MODEL
#   -s PATH     挂载自定义 skills 目录到容器内
#   -c CMD      自定义启动命令(默认 bash)
#   -h          帮助
set -euo pipefail

IMAGE="crpi-qiclkwmeg0rcfork.cn-hangzhou.personal.cr.aliyuncs.com/dfctl/agent-env:latest"
VOLUMES_ROOT="$HOME/agent-volumes"
DEFAULT_PROXY="http://127.0.0.1:7890"

username=""
proxy=""
persist=false
model=""
skills=""
cmd="bash"

usage() {
  grep '^#' "$0" | tail -n +2 | sed 's/^#//' | sed 's/^ //'
  exit 0
}

while getopts "u:xX:pm:s:c:h" opt; do
  case $opt in
    u) username="$OPTARG" ;;
    x) proxy="$DEFAULT_PROXY" ;;
    X) proxy="http://$OPTARG" ;;
    p) persist=true ;;
    m) model="$OPTARG" ;;
    s) skills="$OPTARG" ;;
    c) cmd="$OPTARG" ;;
    h) usage ;;
    *) usage ;;
  esac
done

[[ -z "$username" ]] && username="agent-$(head -c4 /dev/urandom | xxd -p)"

args=(docker run -it --rm --network host --hostname "$username")

if [[ -n "$proxy" ]]; then
  args+=(-e "HTTPS_PROXY=$proxy" -e "HTTP_PROXY=$proxy")
  echo "proxy:   $proxy"
fi

if [[ -n "$model" ]]; then
  args+=(-e "ANTHROPIC_MODEL=$model")
  echo "model:   $model"
fi

if $persist; then
  vol_dir="$VOLUMES_ROOT/$username/.claude"
  mkdir -p "$vol_dir"
  args+=(-v "$vol_dir:/home/agent/.claude")
  echo "persist: $vol_dir"
fi

if [[ -n "$skills" ]]; then
  skills="$(cd "$skills" && pwd)"
  args+=(-v "$skills:/home/agent/.claude/skills:ro")
  echo "skills:  $skills → /home/agent/.claude/skills"
fi

args+=("$IMAGE")

echo "user:    $username"
echo "image:   $IMAGE"
echo "cmd:     $cmd"
echo "---"

exec "${args[@]}" $cmd
