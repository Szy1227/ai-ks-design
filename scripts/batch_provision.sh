#!/usr/bin/env bash
# 批量创建多节点
# 用法:
#   ./scripts/batch_provision.sh 100-105        # 创建 node-100 到 node-105
#   ./scripts/batch_provision.sh 100 101 102    # 创建指定节点
#   ./scripts/batch_provision.sh 5              # 创建 5 个节点（从 max+1 开始）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESIGN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }

# 解析参数
parse_nodes() {
  local args=("$@")
  local nodes=()
  
  for arg in "${args[@]}"; do
    if [[ "$arg" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      # 范围: 100-105
      local start="${BASH_REMATCH[1]}"
      local end="${BASH_REMATCH[2]}"
      for ((i=start; i<=end; i++)); do
        nodes+=("$i")
      done
    elif [[ "$arg" =~ ^[0-9]+$ ]]; then
      # 单个节点号
      nodes+=("$arg")
    else
      log_warn "忽略无效参数: $arg"
    fi
  done
  
  echo "${nodes[@]}"
}

# 获取下一个可用节点号
get_next_nodes() {
  local count="$1"
  local workspace="${DESIGN_ROOT}/workspace"
  local max=99
  
  # 找到最大节点号
  if [[ -d "$workspace" ]]; then
    for d in "${workspace}"/node-*; do
      [[ -d "$d" ]] || continue
      local base
      base="$(basename "$d")"
      if [[ "$base" =~ ^node-([0-9]+)$ ]]; then
        local n="${BASH_REMATCH[1]}"
        if (( n > max )); then max=$n; fi
      fi
    done
  fi
  
  local nodes=()
  for ((i=1; i<=count; i++)); do
    nodes+=("$((max + i))")
  done
  
  echo "${nodes[@]}"
}

# 创建单节点
create_node() {
  local n="$1"
  log_info "创建节点 node-${n}..."
  "${SCRIPT_DIR}/provision.sh" "$n"
}

# 主流程
main() {
  local nodes=()
  
  if [[ $# -eq 0 ]]; then
    echo "用法:"
    echo "  $0 100-105        # 创建 node-100 到 node-105"
    echo "  $0 100 101 102    # 创建指定节点"
    echo "  $0 5              # 创建 5 个节点（从 max+1 开始）"
    exit 1
  fi
  
  # 检查是否是单个数字（表示数量）
  if [[ $# -eq 1 && "$1" =~ ^[0-9]+$ && "$1" -lt 100 ]]; then
    nodes=($(get_next_nodes "$1"))
    log_info "将创建 ${#nodes[@]} 个节点: ${nodes[*]}"
  else
    nodes=($(parse_nodes "$@"))
  fi
  
  if [[ ${#nodes[@]} -eq 0 ]]; then
    log_warn "没有有效的节点号"
    exit 1
  fi
  
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  批量创建节点: ${nodes[*]}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  local success=0
  local failed=0
  
  for n in "${nodes[@]}"; do
    echo ""
    if create_node "$n"; then
      ((success++))
    else
      ((failed++))
      log_warn "节点 node-${n} 创建失败"
    fi
  done
  
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  批量创建完成"
  echo "  成功: ${success}  失败: ${failed}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  # 显示节点列表
  echo ""
  echo "节点列表:"
  docker ps --format "table {{.Names}}\t{{.Ports}}" | grep -E "NAMES|node-"
}

main "$@"
