# 贡献指南

感谢你愿意花时间改进 `ai-ks-design`。下面是协作方式与提交流程，尽量让 PR 一次合并。

## 适合贡献什么

- README / 文档：新手路径、截图、GIF 演示、踩坑补充
- 脚本与编排：`scripts/*.sh`、`provision.sh` 的可观测性、错误提示、边界情况
- 与下游仓库的约定：挂载路径、端口、环境变量（改动时请同步文档）

## 开发前准备

- 本机：**Docker**、**Terraform**、**Git**，且当前用户具备 Docker 执行权限
- 克隆本仓库后，按需阅读 [README.md](README.md) 的「一键部署」与「脚本说明」

## 提交流程

1. **开个 Issue**（或先在 Discussion 里对齐），说明场景与期望行为  
2. **建分支**：`git checkout -b feat/short-description`  
3. **小步提交**：每个 commit 聚焦一个主题，信息用英文或中文完整句子均可  
4. **自测**：至少跑通与你改动相关的主路径（例如 `./scripts/provision.sh` 或 `./scripts/teardown.sh`）  
5. **发 Pull Request**：在描述里写清「动机 / 变更点 / 如何验证」，并关联 Issue

## 脚本与风格

- Shell：优先 `bash`，使用 `set -euo pipefail`；保持与现有脚本相同的缩进与输出风格  
- 避免引入无必要的新依赖；确需新增请在 README 中说明  
- `workspace/` 已 `.gitignore`，请勿将本地节点目录、密钥、state 提交进仓库

## Issue 与版本

- Bug 请用 [Bug 报告](.github/ISSUE_TEMPLATE/bug_report.md) 模板，便于复现  
- 功能建议请用 [功能建议](.github/ISSUE_TEMPLATE/feature_request.md)  
- 发版时可参考 [发版说明模板](docs/release-notes-template.md)

再次感谢。
