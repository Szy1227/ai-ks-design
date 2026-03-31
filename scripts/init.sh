#!/usr/bin/env bash
# 一键初始化环境：安装依赖、克隆项目
# 用法:
#   curl -fsSL https://raw.githubusercontent.com/Szy1227/ai-ks-design/main/scripts/init.sh | bash
#   或本地执行: ./scripts/init.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESIGN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

step() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  $*"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# 检测系统
detect_os() {
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    echo "$ID"
  else
    log_error "无法检测操作系统"
    exit 1
  fi
}

# 安装 Docker
install_docker() {
  if command -v docker &>/dev/null; then
    log_info "Docker 已安装: $(docker --version)"
    return 0
  fi

  log_info "安装 Docker..."
  local os
  os=$(detect_os)

  case "$os" in
    ubuntu|debian)
      sudo apt-get update
      sudo apt-get install -y ca-certificates curl gnupg
      sudo install -m 0755 -d /etc/apt/keyrings
      
      # 使用阿里云镜像源
      curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
      sudo chmod a+r /etc/apt/keyrings/docker.gpg
      
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://mirrors.aliyun.com/docker-ce/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
      
      sudo apt-get update
      sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      
      # 配置镜像加速
      sudo mkdir -p /etc/docker
      sudo tee /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": [
    "https://docker.m.daocloud.io",
    "https://docker.rainbond.cc",
    "https://dockerhub.icu"
  ]
}
EOF
      sudo systemctl daemon-reload
      sudo systemctl restart docker
      sudo systemctl enable docker
      
      # 当前用户加入 docker 组
      sudo usermod -aG docker "$USER"
      log_warn "请重新登录以使 docker 组权限生效"
      ;;
    *)
      log_error "不支持的操作系统: $os，请手动安装 Docker"
      exit 1
      ;;
  esac
  
  log_info "Docker 安装完成"
}

# 安装 Terraform
install_terraform() {
  if command -v terraform &>/dev/null; then
    log_info "Terraform 已安装: $(terraform version | head -1)"
    return 0
  fi

  log_info "安装 Terraform..."
  local os
  os=$(detect_os)

  case "$os" in
    ubuntu|debian)
      sudo apt-get update
      sudo apt-get install -y gnupg software-properties-common wget
      
      wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
      sudo chmod a+r /usr/share/keyrings/hashicorp-archive-keyring.gpg
      
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(. /etc/os-release && echo "$VERSION_CODENAME") main" | sudo tee /etc/apt/sources.list.d/hashicorp.list > /dev/null
      
      sudo apt-get update
      sudo apt-get install -y terraform
      ;;
    *)
      log_error "不支持的操作系统: $os，请手动安装 Terraform"
      exit 1
      ;;
  esac
  
  log_info "Terraform 安装完成"
}

# 检查 SSH 密钥
check_ssh_key() {
  log_info "检查 SSH 密钥配置..."
  
  if [[ ! -d ~/.ssh ]]; then
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
  fi
  
  # 检查是否有可用的 SSH 密钥
  local has_key=0
  for key in ~/.ssh/id_rsa ~/.ssh/id_ed25519 ~/.ssh/github_*; do
    if [[ -f "$key" ]]; then
      has_key=1
      log_info "发现 SSH 密钥: $key"
    fi
  done
  
  if [[ $has_key -eq 0 ]]; then
    log_warn "未发现 SSH 密钥，请确保已配置 GitHub SSH 密钥"
    log_warn "生成密钥: ssh-keygen -t ed25519 -C 'your_email@example.com'"
    log_warn "添加到 GitHub: https://github.com/settings/keys"
    return 1
  fi
  
  # 测试 GitHub 连接
  if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
    log_info "GitHub SSH 连接成功"
    return 0
  else
    log_warn "GitHub SSH 连接失败，请检查 SSH config 配置"
    return 1
  fi
}

# 克隆项目
clone_projects() {
  local workspace="${DESIGN_ROOT}/workspace"
  local base="${workspace}/node-base"
  
  log_info "克隆项目仓库..."
  mkdir -p "${base}"
  
  # 克隆或更新各仓库
  local repos=(
    "git@github.com:Szy1227/ai-ks-vue.git:ai-ks-vue"
    "git@github.com:Szy1227/ai-ks-fastapi.git:ai-ks-fastapi"
    "git@github.com:Szy1227/ai-ks-ssh-claude.git:ai-ks-ssh-claude"
    "git@github.com:Szy1227/ai-ks-tools.git:../ai-ks-tools"
  )
  
  for repo_info in "${repos[@]}"; do
    local url="${repo_info%%:*}"
    local dest="${repo_info#*:}"
    
    if [[ "$dest" == ".."* ]]; then
      dest="${workspace}/${dest#../}"
    else
      dest="${base}/${dest}"
    fi
    
    if [[ -d "${dest}/.git" ]]; then
      log_info "更新: $(basename "$dest")"
      git -C "$dest" pull --ff-only
    else
      log_info "克隆: $url -> $dest"
      git clone "$url" "$dest"
    fi
  done
  
  log_info "项目克隆完成"
}

# 验证环境
verify_environment() {
  log_info "验证环境..."
  
  local errors=0
  
  if ! command -v docker &>/dev/null; then
    log_error "Docker 未安装"
    ((errors++))
  fi
  
  if ! command -v terraform &>/dev/null; then
    log_error "Terraform 未安装"
    ((errors++))
  fi
  
  if ! command -v git &>/dev/null; then
    log_error "Git 未安装"
    ((errors++))
  fi
  
  # 检查 docker 权限
  if ! docker ps &>/dev/null; then
    log_warn "Docker 权限不足，请运行: sudo chmod 666 /var/run/docker.sock 或重新登录"
  fi
  
  if [[ $errors -gt 0 ]]; then
    return 1
  fi
  
  log_info "环境验证通过"
  return 0
}

# 主流程
main() {
  step "一键初始化 ai-ks 开发环境"
  
  log_info "系统: $(detect_os)"
  log_info "工作目录: ${DESIGN_ROOT}"
  
  step "1/5 安装 Docker"
  install_docker
  
  step "2/5 安装 Terraform"
  install_terraform
  
  step "3/5 检查 SSH 密钥"
  check_ssh_key || true
  
  step "4/5 克隆项目"
  clone_projects
  
  step "5/5 验证环境"
  verify_environment
  
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  初始化完成！"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "  创建单节点:"
  echo "    ./scripts/provision.sh"
  echo ""
  echo "  创建多节点:"
  echo "    ./scripts/provision.sh 100 101 102"
  echo ""
  echo "  或使用批量脚本:"
  echo "    ./scripts/batch_provision.sh 100-105"
  echo ""
}

main "$@"
