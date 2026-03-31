#!/usr/bin/env bash
# 从 GitHub 维护 workspace/node-base，再复制到 node-<N> 并调用各目录 tf_apply.sh。
# 用法:
#   ./scripts/provision.sh              # 自动节点号: 无 node-<数字> 时为 100，否则 max+1
#   ./scripts/provision.sh <N>          # 指定整数节点号，工作目录 workspace/node-<N>
#   ./scripts/provision.sh --force [N]  # 若 workspace/node-<N> 已存在仍继续（删旧目录后从 node-base 再复制）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESIGN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WORKSPACE_ROOT="${DESIGN_ROOT}/workspace"
BASE_ROOT="${WORKSPACE_ROOT}/node-base"

BASE_VUE_PORT=13000
BASE_FASTAPI_PORT=18000
BASE_SSH_PORT=22000

GIT_VUE="git@github.com:Szy1227/ai-ks-vue.git"
GIT_FASTAPI="git@github.com:Szy1227/ai-ks-fastapi.git"
GIT_SSH="git@github.com:Szy1227/ai-ks-ssh-claude.git"
GIT_TOOLS="git@github.com:Szy1227/ai-ks-tools.git"

step() {
  local num="$1"
  shift
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  步骤 ${num}: $*"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

die() {
  echo "错误: $*" >&2
  exit 1
}

check_prerequisites() {
  local missing=0

  if ! command -v git >/dev/null 2>&1; then
    echo "错误: 未检测到 git。" >&2
    echo "解决: sudo apt-get update && sudo apt-get install -y git" >&2
    missing=1
  fi

  if ! command -v docker >/dev/null 2>&1; then
    echo "错误: 未检测到 Docker。" >&2
    echo "解决: 先运行 ./scripts/init.sh，或按 README 手动安装 Docker。" >&2
    missing=1
  fi

  if ! command -v terraform >/dev/null 2>&1; then
    echo "错误: 未检测到 Terraform。" >&2
    echo "解决: 先运行 ./scripts/init.sh，或按 README 手动安装 Terraform。" >&2
    missing=1
  fi

  if ! command -v id >/dev/null 2>&1; then
    echo "错误: 未检测到 id 命令，无法自动获取当前用户 UID/GID。" >&2
    echo "解决: 安装 coreutils（Ubuntu/Debian: sudo apt-get install -y coreutils）。" >&2
    missing=1
  fi

  if (( missing > 0 )); then
    die "前置条件不满足，请按上方“解决”修复后重试。"
  fi

  if ! docker ps >/dev/null 2>&1; then
    die "当前用户无 Docker 权限。解决: sudo usermod -aG docker $USER 后重新登录，或临时 sudo chmod 666 /var/run/docker.sock。"
  fi
}

clone_or_pull() {
  local url="$1"
  local dest="$2"
  local name
  name="$(basename "$dest")"
  if [[ -d "${dest}/.git" ]]; then
    echo "  [${name}] 已存在，git pull --ff-only"
    git -C "$dest" pull --ff-only
  elif [[ -e "$dest" ]]; then
    die "${dest} 存在但不是 git 仓库"
  else
    echo "  [${name}] git clone"
    git clone "$url" "$dest"
  fi
}

JOB_PIDS=()
JOB_NAMES=()
JOB_LOGS=()

reset_jobs() {
  JOB_PIDS=()
  JOB_NAMES=()
  JOB_LOGS=()
}

start_job() {
  local name="$1"
  shift
  local log_file
  log_file="$(mktemp "/tmp/provision-${name//[^a-zA-Z0-9_-]/_}-XXXX.log")"
  (
    set -euo pipefail
    "$@"
  ) >"${log_file}" 2>&1 &
  JOB_PIDS+=("$!")
  JOB_NAMES+=("$name")
  JOB_LOGS+=("${log_file}")
  echo "  [${name}] 已启动 (pid=$!)"
}

wait_jobs_or_die() {
  local stage="$1"
  local i failed=0

  echo "  等待并行任务完成: ${stage}"
  for i in "${!JOB_PIDS[@]}"; do
    if wait "${JOB_PIDS[$i]}"; then
      echo "  [${JOB_NAMES[$i]}] 完成"
    else
      failed=1
      echo "  [${JOB_NAMES[$i]}] 失败（日志: ${JOB_LOGS[$i]}）" >&2
    fi
  done

  if (( failed > 0 )); then
    echo "" >&2
    echo "===== 并行任务失败详情: ${stage} =====" >&2
    for i in "${!JOB_PIDS[@]}"; do
      if [[ -f "${JOB_LOGS[$i]}" ]]; then
        echo "--- ${JOB_NAMES[$i]} ---" >&2
        sed -n '1,200p' "${JOB_LOGS[$i]}" >&2
      fi
    done
    die "${stage} 存在失败任务，请根据上方日志修复后重试。"
  fi

  for i in "${!JOB_LOGS[@]}"; do
    rm -f "${JOB_LOGS[$i]}"
  done
  reset_jobs
}

sync_tools_repo() {
  clone_or_pull "${GIT_TOOLS}" "${TOOLS_CLONE}"
  mkdir -p "${TOOLS_PLUGINS}"
}

sync_base_vue_repo() {
  clone_or_pull "${GIT_VUE}" "${BASE_ROOT}/ai-ks-vue"
}

sync_base_fastapi_repo() {
  clone_or_pull "${GIT_FASTAPI}" "${BASE_ROOT}/ai-ks-fastapi"
}

sync_base_ssh_repo() {
  clone_or_pull "${GIT_SSH}" "${BASE_ROOT}/ai-ks-ssh-claude"
}

apply_vue() {
  cd "${ROOT}/ai-ks-vue"
  chmod +x tf_apply.sh 2>/dev/null || true
  ./tf_apply.sh "${VUE_PORT}" code "${STACK_SUFFIX}" "${NETWORK_NAME}" "http://ai-ks-fastapi${STACK_SUFFIX}:8000"
}

apply_fastapi() {
  cd "${ROOT}/ai-ks-fastapi"
  chmod +x tf_apply.sh 2>/dev/null || true
  ./tf_apply.sh "${FASTAPI_PORT}" code "${STACK_SUFFIX}" "${NETWORK_NAME}"
}

apply_ssh() {
  cd "${ROOT}/ai-ks-ssh-claude"
  chmod +x tf_apply.sh 2>/dev/null || true
  TF_VAR_stack_suffix="${STACK_SUFFIX}" ./tf_apply.sh
}

derive_next_n() {
  local max=-1
  local any=0
  local d base
  shopt -s nullglob
  for d in "${WORKSPACE_ROOT}"/node-*; do
    [[ -d "$d" ]] || continue
    base="$(basename "$d")"
    if [[ "$base" =~ ^node-([0-9]+)$ ]]; then
      any=1
      local n="${BASH_REMATCH[1]}"
      if (( n > max )); then max=$n; fi
    fi
  done
  shopt -u nullglob
  if [[ "$any" -eq 0 ]]; then
    echo 100
  else
    echo $((max + 1))
  fi
}

normalize_node_arg() {
  local a="${1:-}"
  if [[ -z "$a" ]]; then
    echo ""
    return
  fi
  if [[ "$a" =~ ^node-([0-9]+)$ ]]; then
    echo "${BASH_REMATCH[1]}"
    return
  fi
  if [[ "$a" =~ ^[0-9]+$ ]]; then
    echo "$a"
    return
  fi
  die "无效的节点参数: $a（应为整数或 node-<整数>）"
}

copy_node_from_base() {
  local name
  for name in ai-ks-vue ai-ks-fastapi ai-ks-ssh-claude; do
    [[ -d "${BASE_ROOT}/${name}/.git" ]] || die "node-base 缺少 ${name}，请先完成步骤「维护 node-base」"
    echo "  复制 ${name} <- node-base"
    rm -rf "${ROOT}/${name}"
    cp -a "${BASE_ROOT}/${name}" "${ROOT}/"
  done
}

FORCE=0
POS=()
for arg in "$@"; do
  if [[ "$arg" == "--force" ]]; then
    FORCE=1
  else
    POS+=("$arg")
  fi
done

mkdir -p "${WORKSPACE_ROOT}"
check_prerequisites

step "1/7" "解析节点号 N 与目录"
N_RAW="${POS[0]:-}"
if [[ -n "$N_RAW" ]]; then
  N="$(normalize_node_arg "$N_RAW")" || exit 1
  echo "  使用指定节点号 N=${N}"
else
  N="$(derive_next_n)"
  echo "  自动推导节点号 N=${N}（无 node-<数字> 时为 100，否则为最大后缀 +1）"
fi

ROOT="${WORKSPACE_ROOT}/node-${N}"
STACK_SUFFIX="-node-${N}"
echo "  工作目录 ROOT=${ROOT}"

if [[ -d "$ROOT" ]] && [[ "$FORCE" -ne 1 ]]; then
  die "目录已存在: ${ROOT}。请先 ./scripts/teardown.sh ${N} --rm-root 或加上 --force"
fi

VUE_PORT=$((BASE_VUE_PORT + N))
FASTAPI_PORT=$((BASE_FASTAPI_PORT + N))
SSH_PORT=$((BASE_SSH_PORT + N))

echo "  端口: Vue=${VUE_PORT}  FastAPI=${FASTAPI_PORT}  SSH=${SSH_PORT}"
echo "  容器名后缀 stack_suffix=${STACK_SUFFIX}"

TOOLS_CLONE="${WORKSPACE_ROOT}/ai-ks-tools"
TOOLS_PLUGINS="${TOOLS_CLONE}/terraform/plugins"
export TF_INIT_PLUGIN_DIR="${TOOLS_PLUGINS}"

step "2/7" "启动并行下载/更新（ai-ks-tools + node-base 三应用）"
mkdir -p "${BASE_ROOT}"
reset_jobs
start_job "ai-ks-tools" sync_tools_repo
start_job "ai-ks-vue(base)" sync_base_vue_repo
start_job "ai-ks-fastapi(base)" sync_base_fastapi_repo
start_job "ai-ks-ssh-claude(base)" sync_base_ssh_repo

step "3/7" "等待并行下载/更新完成"
wait_jobs_or_die "下载/更新阶段"
echo "  插件目录: ${TF_INIT_PLUGIN_DIR}（请按需填入 provider，见 ai-ks-tools 说明）"

step "4/7" "准备工作目录 workspace/node-<N>"
if [[ -d "$ROOT" ]] && [[ "$FORCE" -eq 1 ]]; then
  echo "  --force: 移除已有 ${ROOT}"
  rm -rf "${ROOT}"
fi
mkdir -p "${ROOT}"
echo "  已确保存在: ${ROOT}"

step "5/7" "从 node-base 复制到 node-<N>（含 .git，各节点独立仓库副本）"
copy_node_from_base

SSH_TFVARS="${ROOT}/ai-ks-ssh-claude/ssh.auto.tfvars"
step "6/7" "生成 SSH 模块配置 ${SSH_TFVARS}"
cat >"${SSH_TFVARS}" <<EOF
# 由 ai-ks-design/scripts/provision.sh 生成，可手工修改后重新执行 ai-ks-ssh-claude/tf_apply.sh
external_port = ${SSH_PORT}
mounts = [
  { host_path = "../ai-ks-vue/code", container_path = "/home/ai-ks/vue", read_only = false },
  { host_path = "../ai-ks-fastapi/code", container_path = "/home/ai-ks/fastapi", read_only = false },
]
EOF
echo "  已写入 external_port 与前后端 code 挂载（容器内 /home/ai-ks/vue、/home/ai-ks/fastapi）"

step "7/7" "Terraform 拉起容器（TF_INIT_PLUGIN_DIR=${TF_INIT_PLUGIN_DIR}）"

# 创建节点专用 Docker 网络（用于 Vue 和 FastAPI 联动）
NETWORK_NAME="ai-ks-network-${N}"
if ! docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
  echo "  创建 Docker 网络: ${NETWORK_NAME}"
  docker network create "$NETWORK_NAME"
else
  echo "  Docker 网络已存在: ${NETWORK_NAME}"
fi

echo "  并行拉起: ai-ks-vue / ai-ks-fastapi / ai-ks-ssh-claude"
reset_jobs
start_job "ai-ks-vue(apply)" apply_vue
start_job "ai-ks-fastapi(apply)" apply_fastapi
start_job "ai-ks-ssh-claude(apply)" apply_ssh
wait_jobs_or_die "创建阶段（Terraform apply）"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  完成: 节点 node-${N}"
echo "  目录: ${ROOT}"
echo "  访问: Vue http://<宿主机>:${VUE_PORT}  FastAPI http://<宿主机>:${FASTAPI_PORT}"
echo "  SSH:  见上方「SSH Login Info」"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
