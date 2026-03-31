#!/usr/bin/env bash
# 一键清理 workspace：仅当 ai-ks-design 与 workspace 下各 Git 仓库均无未提交变更时执行；
# 否则打印说明与各仓库 git status，并退出码 1。
# 清理：对各 node-<数字> 执行 teardown --rm-root（重命名为 rm-node-<N>）；不删除 ai-ks-tools、node-base。
# 用法:
#   ./scripts/clean_workspace.sh           # 需交互确认
#   ./scripts/clean_workspace.sh -y        # 跳过确认（等同 --yes）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESIGN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WORKSPACE_ROOT="${DESIGN_ROOT}/workspace"

die() {
  echo "错误: $*" >&2
  exit 1
}

SKIP_CONFIRM=0
for arg in "$@"; do
  case "$arg" in
    -y|--yes) SKIP_CONFIRM=1 ;;
    -h|--help)
      echo "用法: $0 [-y|--yes]"
      exit 0
      ;;
    *)
      die "未知参数: $arg（仅支持 -y / --yes）"
      ;;
  esac
done

collect_git_roots() {
  GIT_ROOTS=()
  if [[ -d "${DESIGN_ROOT}/.git" ]]; then
    GIT_ROOTS+=("${DESIGN_ROOT}")
  fi
  if [[ -d "${WORKSPACE_ROOT}/ai-ks-tools/.git" ]]; then
    GIT_ROOTS+=("${WORKSPACE_ROOT}/ai-ks-tools")
  fi
  local sub
  for sub in ai-ks-vue ai-ks-fastapi ai-ks-ssh-claude; do
    if [[ -d "${WORKSPACE_ROOT}/node-base/${sub}/.git" ]]; then
      GIT_ROOTS+=("${WORKSPACE_ROOT}/node-base/${sub}")
    fi
  done
  local d base sorted
  shopt -s nullglob
  local nodes=( "${WORKSPACE_ROOT}"/node-* )
  shopt -u nullglob
  mapfile -t sorted < <(printf '%s\n' "${nodes[@]:-}" | sort -V)
  for d in "${sorted[@]}"; do
    [[ -d "$d" ]] || continue
    base="$(basename "$d")"
    [[ "$base" =~ ^node-[0-9]+$ ]] || continue
    for sub in ai-ks-vue ai-ks-fastapi ai-ks-ssh-claude; do
      if [[ -d "${d}/${sub}/.git" ]]; then
        GIT_ROOTS+=("${d}/${sub}")
      fi
    done
  done
}

collect_git_roots

DIRTY_REPOS=()
for root in "${GIT_ROOTS[@]}"; do
  if [[ -n "$(git -C "$root" status --porcelain 2>/dev/null || true)" ]]; then
    DIRTY_REPOS+=("$root")
  fi
done

if [[ ${#DIRTY_REPOS[@]} -gt 0 ]]; then
  echo ""
  echo "以下仓库存在未提交变更（含未跟踪文件），已中止清理。请先提交、暂存或丢弃修改后再试。"
  echo ""
  for root in "${DIRTY_REPOS[@]}"; do
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "=== ${root} ==="
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    git -C "$root" status
    echo ""
  done
  exit 1
fi

if [[ ${#GIT_ROOTS[@]} -eq 0 ]]; then
  echo "未发现需检查的 Git 仓库（可能尚未 provision）。仍将尝试对各 node-<数字> 做 teardown 标记。"
fi

if [[ "$SKIP_CONFIRM" -ne 1 ]]; then
  read -r -p "确认清理：对所有 node-<数字> 执行 destroy 并重命名为 rm-node-<N>（保留 ai-ks-tools、node-base）? [y/N] " ans || true
  case "${ans:-}" in
    y|Y|yes|YES) ;;
    *) echo "已取消。"; exit 0 ;;
  esac
fi

echo ""
echo "开始清理…"

shopt -s nullglob
NODE_LIST=( "${WORKSPACE_ROOT}"/node-* )
shopt -u nullglob
mapfile -t NODE_SORTED < <(printf '%s\n' "${NODE_LIST[@]:-}" | sort -V)

for d in "${NODE_SORTED[@]}"; do
  [[ -d "$d" ]] || continue
  base="$(basename "$d")"
  if [[ "$base" =~ ^node-([0-9]+)$ ]]; then
    n="${BASH_REMATCH[1]}"
    echo ""
    echo ">>> teardown node-${n} (--rm-root -> rm-node-${n})"
    chmod +x "${SCRIPT_DIR}/teardown.sh" 2>/dev/null || true
    "${SCRIPT_DIR}/teardown.sh" "$n" --rm-root
  fi
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  一键清理完成：已保留 workspace/ai-ks-tools、workspace/node-base。"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
