#!/usr/bin/env bash
# 按顺序销毁节点下三个 Terraform 栈；可选将目录标记为已删除（重命名，不删代码）。
# 用法:
#   ./scripts/teardown.sh <N|node-N>           # N 为整数，如 100 或 node-100
#   ./scripts/teardown.sh <N|node-N> --rm-root  # destroy 后将 workspace/node-<N> 重命名为 workspace/rm-node-<N>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESIGN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WORKSPACE_ROOT="${DESIGN_ROOT}/workspace"

die() {
  echo "错误: $*" >&2
  exit 1
}

normalize_node_arg() {
  local a="${1:-}"
  if [[ "$a" =~ ^node-([0-9]+)$ ]]; then
    echo "${BASH_REMATCH[1]}"
    return
  fi
  if [[ "$a" =~ ^[0-9]+$ ]]; then
    echo "$a"
    return
  fi
  die "无效的节点参数: ${a:-空}（应为整数或 node-<整数>）"
}

RM_ROOT=0
ARGS=()
for arg in "$@"; do
  if [[ "$arg" == "--rm-root" ]]; then
    RM_ROOT=1
  else
    ARGS+=("$arg")
  fi
done

[[ ${#ARGS[@]} -ge 1 ]] || die "用法: $0 <N|node-N> [--rm-root]"

N="$(normalize_node_arg "${ARGS[0]}")" || exit 1
ROOT="${WORKSPACE_ROOT}/node-${N}"

[[ -d "$ROOT" ]] || die "目录不存在: ${ROOT}"

step() {
  local num="$1"
  shift
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  步骤 ${num}: $*"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

run_destroy() {
  local name="$1"
  local dir="${ROOT}/${name}"
  if [[ ! -d "$dir" ]]; then
    echo "  跳过（目录不存在）: ${dir}"
    return 0
  fi
  if [[ ! -f "${dir}/tf_destroy.sh" ]]; then
    echo "  跳过（无 tf_destroy.sh）: ${dir}"
    return 0
  fi
  echo "  执行: ${dir}/tf_destroy.sh"
  chmod +x "${dir}/tf_destroy.sh" 2>/dev/null || true
  ( cd "$dir" && ./tf_destroy.sh )
}

step "1/4" "销毁 ai-ks-ssh-claude（SSH）"
run_destroy "ai-ks-ssh-claude"

step "2/4" "销毁 ai-ks-fastapi"
run_destroy "ai-ks-fastapi"

step "3/4" "销毁 ai-ks-vue"
run_destroy "ai-ks-vue"

step "4/4" "收尾"
if [[ "$RM_ROOT" -eq 1 ]]; then
  MARK="${WORKSPACE_ROOT}/rm-node-${N}"
  if [[ -e "$MARK" ]]; then
    die "标记目录已存在: ${MARK}，请先手工移动或删除后再试"
  fi
  echo "  标记删除（重命名，不删文件）: ${ROOT} -> ${MARK}"
  mv "${ROOT}" "${MARK}"
  echo "  已完成。"
else
  echo "  保留工作目录 ${ROOT}（仅销毁容器）。若要标记删除请追加 --rm-root"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  teardown 完成: node-${N}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
