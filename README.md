# ai-ks-design

**把与你绑定的“改需求”，变成对方能自助搞定的一键环境。** 一条命令拉起前后端 + SSH 开发容器，需求方进去就能对着真实仓库用 AI 写代码、做小迭代——**细碎问题先找 AI，别先找你**；你守住评审与发布即可。前后端协作从“反复被打断”变成**可规模化的交付**：你的时间越省下来，整体效率越高，**你的工作方式也越值得被持续优化**。

## 协作模式对比与本项目优势

在「用户能参与改代码 + 开发仍能把关发布」的前提下，常见有三种路径。`ai-ks-design` 对应第三种：**开发一键交付标准化、可隔离的多节点运行环境，用户进入即可对着真实仓库用 AI 做增量开发**，把时间花在实现与迭代上，而不是长篇需求文档或本机装环境。

| 维度 | 模式一：文档链自己改 | 模式二：开权限自建环境 | 模式三：给环境（本项目） |
|------|----------------------|------------------------|--------------------------|
| 用户前期负担 | 写需求文档、提 issue，反复对齐理解 | 找机器、配系统/网络/密钥/依赖，搭出一套可跑环境 | 拿到端口与 SSH，进入标配环境即可 |
| 开发侧负担 | 反复「翻译」需求，再 AI 辅助实现 | 开权限 + 仍可能要答疑环境问题 | **一键 `provision`（可多节点）**，审核合并与发布流程不变 |
| 迭代形态 | 用户 ↔ 文档 ↔ 开发，回合多 | 用户本机环境各异，问题难复现 | 镜像与挂载约定统一，前后端 + SSH 一体，仓库**整库挂载**便于容器内 `git diff` |
| 适用场景 | 强流程、重书面需求 | 用户已有成熟本地工程能力 | **既要用户动手改，又要省沟通与环境成本** |


**小结：`ai-ks-design` 带来的对比优点**

- **把用户的「时间」从写长文档、折腾环境，挪到改代码与和 AI 协作上**；需求更多在对话与代码增量里闭环。
- **开发侧用脚本 + Terraform 固定交付物**：Vue / FastAPI / SSH 同节点联动、端口按节点号递增，可多用户多节点并行。
- **挂载的是完整仓库而非单个子目录**，容器内可当正常 Git 工作区使用（如 `git status`、`git diff`），减少「只有代码没有仓库上下文」的摩擦。

## 一键部署

### 方式一：全新环境一键初始化

```bash
# 克隆项目
git clone git@github.com:Szy1227/ai-ks-design.git
cd ai-ks-design

# 一键初始化（安装 Docker、Terraform、克隆依赖项目）
./scripts/init.sh

# 重新登录使 Docker 权限生效，然后创建节点
./scripts/provision.sh
```

初始化后可继续进行 AI 工具配置（容器内已内置 Claude + 智谱工具）：

```bash
# 1) 先通过 SSH 进入节点（端口按 22000 + N）
ssh ai-ks@<宿主机IP> -p <SSH端口>

# 2) 在容器内配置智谱工具 API Key
npx @z_ai/coding-helper
```

> 说明：SSH 容器已内置 `@anthropic-ai/claude-code` 与 `@z_ai/coding-helper`，首次进入后按提示完成 key 配置即可开始 AI-coding。

删除环境（示例）：

```bash
./scripts/teardown.sh node-100 --rm-root
```

### 前提条件

- GitHub SSH 密钥已配置（克隆私有仓库需要）
- 服务器可访问 GitHub 和 Docker Hub
- 已安装 `git`、`docker`、`terraform`、`id`（`coreutils`）
- 当前用户有 Docker 与 Terraform 执行权限（建议加入 `docker` 组并重新登录）

> `provision.sh` 和各模块 `tf_apply.sh` 会自动获取当前用户 `UID/GID`（`id -u` / `id -g`）。  
> 若条件不满足，脚本会直接报错并给出对应修复命令。

## 安装依赖

### Docker

Ubuntu 24.04 安装 Docker（使用阿里云镜像源）：

```bash
# 安装依赖
sudo apt-get update && sudo apt-get install -y ca-certificates curl gnupg

# 添加 Docker GPG key 和软件源
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://mirrors.aliyun.com/docker-ce/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 安装 Docker
sudo apt-get update && sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 启动并设置开机自启
sudo systemctl start docker && sudo systemctl enable docker

# 将当前用户加入 docker 组（需重新登录生效）
sudo usermod -aG docker $USER

# 配置国内镜像加速（可选，解决 Docker Hub 访问慢）
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
sudo systemctl daemon-reload && sudo systemctl restart docker
```

### Terraform

Ubuntu 24.04 安装 Terraform（使用 HashiCorp 官方源）：

```bash
# 安装依赖
sudo apt-get update && sudo apt-get install -y gnupg software-properties-common

# 添加 HashiCorp GPG key
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
sudo chmod a+r /usr/share/keyrings/hashicorp-archive-keyring.gpg

# 添加软件源
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(. /etc/os-release && echo "$VERSION_CODENAME") main" | sudo tee /etc/apt/sources.list.d/hashicorp.list > /dev/null

# 安装 Terraform
sudo apt-get update && sudo apt-get install -y terraform
```

## 资源需求

### 最低配置

| 项目 | 最低要求 | 推荐配置 |
|------|----------|----------|
| CPU | 2 核 | 4 核+ |
| 内存 | 1.5 GB | 4 GB+ |
| 磁盘 | 20 GB | 50 GB+ |

### 单节点资源占用

每个节点（Vue + FastAPI + SSH 容器）约占用：

| 服务 | 内存 | CPU（空闲） |
|------|------|-------------|
| Vue (Node.js) | ~100 MB | ~0% |
| FastAPI (Python) | ~50 MB | ~1% |
| SSH | ~15 MB | ~0% |
| **合计** | **~165 MB** | **~1%** |

### 节点数量建议

| 内存 | 建议节点数 |
|------|------------|
| 1.5 GB | ≤ 3 个 |
| 2 GB | ≤ 5 个 |
| 4 GB | ≤ 10 个 |

> 💡 内存紧张时，可使用 `./scripts/teardown.sh <N>` 拆除不活跃节点释放资源。

## 前置条件

- `git`、`terraform`、Docker
- 可访问并克隆下游仓库（见下方「相关仓库」）
- `ai-ks-tools` 中配置好 Terraform provider（`terraform/plugins/`，见该仓库说明）

## 快速开始

在仓库根目录执行：

```bash
./scripts/provision.sh              # 自动节点号 N（无 node-<数字> 时为 100，否则 max+1）
./scripts/provision.sh 105          # 指定 N=105 → workspace/node-105
./scripts/provision.sh --force 105  # 若 node-105 已存在：删除后从 node-base 再复制并 apply
```

拆除与清理：

```bash
./scripts/teardown.sh 100                    # 各子目录 tf_destroy，保留 workspace/node-100
./scripts/teardown.sh node-100 --rm-root     # destroy 后将目录重命名为 rm-node-100

./scripts/clean_workspace.sh                 # 交互确认；要求相关 git 仓库工作区干净
./scripts/clean_workspace.sh -y
```

## 端口（节点号 N）

| 服务    | 宿主机端口   |
|---------|--------------|
| Vue     | `13000 + N`  |
| FastAPI | `18000 + N`  |
| SSH     | `22000 + N`  |

## 脚本说明

| 脚本 | 作用 |
|------|------|
| `scripts/init.sh` | 一键初始化环境：安装 Docker、Terraform、克隆依赖项目 |
| `scripts/provision.sh` | 创建单节点：维护 `workspace/node-base`、复制到 `node-<N>`、执行 Terraform |
| `scripts/batch_provision.sh` | 批量创建多节点：支持范围（100-105）、列表（100 101 102）、数量（5） |
| `scripts/teardown.sh` | 按 SSH → FastAPI → Vue 顺序 `destroy`；可选 `--rm-root` 重命名节点目录 |
| `scripts/clean_workspace.sh` | 校验 git 干净后，对各 `node-<数字>` 执行 teardown `--rm-root` |

## 目录约定

`workspace/` 已列入本仓库 `.gitignore`。

```
workspace/
  ai-ks-tools/              # terraform/plugins 为共用插件目录
  node-base/                # 三应用唯一上游（git pull 后复制到各节点）
    ai-ks-vue/
    ai-ks-fastapi/
    ai-ks-ssh-claude/
  node-<N>/                 # 自 node-base 复制，独立 .git 与 terraform state
  rm-node-<N>/              # teardown --rm-root 或 clean_workspace 后的目录
```

编排生成的 `ssh.auto.tfvars` 位于各节点下的 `ai-ks-ssh-claude/`，且在该仓库 `.gitignore` 中。

## 手动部署（不用编排脚本）

在任意克隆目录内单独执行 `./tf_apply.sh` / `./tf_destroy.sh`。若位于 `workspace/node-<N>/...` 且存在 `workspace/ai-ks-tools/terraform/plugins`，会自动用作 `terraform init -plugin-dir`。

## 常见问题

### Docker socket 权限不足

运行 `provision.sh` 时报错：
```
permission denied while trying to connect to the Docker daemon socket at unix:///var/run/docker.sock
```

**解决方案**：

方法一（临时）：
```bash
sudo chmod 666 /var/run/docker.sock
```

方法二（永久，需重新登录）：
```bash
sudo usermod -aG docker $USER
# 重新登录后生效
```

### 自动获取 UID/GID 失败

运行 `provision.sh` 或 `tf_apply.sh` 时，若看到“无法获取当前 UID/GID”或“缺少 id 命令”：

```bash
# 安装 id 命令（coreutils）
sudo apt-get update && sudo apt-get install -y coreutils

# 验证
id -u
id -g
```

若在非常规环境中未设置用户名，可手动指定：

```bash
export TF_VAR_username="$USER"
export TF_VAR_user_uid="$(id -u)"
export TF_VAR_user_gid="$(id -g)"
```

### Git clone 失败（SSH 密钥问题）

报错 `Permission denied (publickey)` 时，检查 SSH 配置：

```bash
# 查看可用密钥
ls -la ~/.ssh/

# 检查 SSH config
cat ~/.ssh/config

# 测试 GitHub 连接
ssh -T git@github.com
```

确保 `~/.ssh/config` 指向正确的密钥文件：
```
Host github.com
    IdentityFile ~/.ssh/your_private_key
    IdentitiesOnly yes
```

### Docker Hub 拉取镜像超时

国内访问 Docker Hub 可能超时，需配置镜像加速（见上方 Docker 安装章节）。

### Terraform provider 下载慢

已配置 `-plugin-dir` 使用本地缓存。若首次下载慢，可手动下载 provider 到 `ai-ks-tools/terraform/plugins/`。

## 相关仓库

- [ai-ks-vue](https://github.com/Szy1227/ai-ks-vue)
- [ai-ks-fastapi](https://github.com/Szy1227/ai-ks-fastapi)
- [ai-ks-ssh-claude](https://github.com/Szy1227/ai-ks-ssh-claude)
- [ai-ks-tools](https://github.com/Szy1227/ai-ks-tools)（Terraform 插件与工具）
