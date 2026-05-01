# cc-profiles

> Claude Code 多模型 Profile 管理器 — 不同终端窗口跑不同模型，互不干扰。

`claude --model` 或改 `settings.json` 都是全局生效，多开就冲突。cc-profiles 通过环境变量隔离，每个 shell 进程独立，真正支持多开。

## ✨ 特性

- 🔄 **多模型并行** — 不同终端窗口跑不同模型，互不影响
- 🔌 **兼容所有 Anthropic 协议 API** — GLM、DeepSeek、Mimo、Qwen 等
- 📋 **一键同步** — 从现有 `settings.json` 导入当前配置
- 📦 **批量导入** — TSV 文件或管道一次性导入多个模型
- 🎯 **自定义 alias** — 想叫 `copus`、`cds`、`cglm` 随你
- 🔒 **API Key 本地存储** — 不上传任何远程服务
- 🔍 **自动检测 claude 路径** — 无需手动配置

## 一键安装

```bash
# 推荐：curl 安装，自动同步当前模型
bash <(curl -fsSL https://raw.githubusercontent.com/dongdada29/cc-profiles/main/install.sh)

# 或 git clone
git clone https://github.com/dongdada29/cc-profiles.git
cd cc-profiles && bash install.sh
```

安装后自动完成：
1. 安装 `cc-profiles` 到 `~/.local/bin`
2. 配置 shell rc（zsh/bash 自动检测）
3. 从当前 `settings.json` 同步第一个 profile
4. source 后即可使用 alias 启动

```bash
source ~/.zshrc
cc-profiles list    # 看已同步的模型
```

## 快速开始

```bash
# 方式1: 批量导入（推荐）
cc-profiles batch profiles.tsv

# 方式2: 从当前配置同步
cc-profiles sync

# 方式3: 交互式添加
cc-profiles add glm

# 方式4: 直接编辑
cc-profiles edit
```

## 命令

```
cc-profiles list                列出所有配置
cc-profiles sync                从 settings.json 同步当前配置
cc-profiles batch [file]        批量导入（TSV 或管道）
cc-profiles add [name]          交互式添加新模型
cc-profiles remove [name]       删除配置
cc-profiles use [name]          设置默认模型（写入 settings.json）
cc-profiles edit                用 $EDITOR 编辑配置文件
cc-profiles aliases             显示生成的 alias
cc-profiles glm                直接启动某个 profile
```

## 批量导入

创建 `profiles.tsv`：

```
# key|显示名称|API Base URL|API Key|Model ID
glm|GLM-5.1|https://open.bigmodel.cn/api/anthropic|YOUR_KEY|glm-5.1
deepseek|DeepSeek-v4-pro|https://api.deepseek.com|YOUR_KEY|deepseek-v4-pro
mimo|Mimo-v2.5|https://api.mimo.com/v1|YOUR_KEY|mimo-v2.5
```

```bash
# 从文件导入
cc-profiles batch profiles.tsv

# 从管道导入
echo "glm|GLM-5.1|https://open.bigmodel.cn/api/anthropic|KEY|glm-5.1" | cc-profiles batch

# 交互式粘贴
cc-profiles batch
# 然后逐行粘贴，空行结束
```

## 自定义 Alias

```bash
cc-profiles add glm
# ...
# Custom alias [cglm]: copus    ← 自己取名
```

或直接编辑配置文件：

```json
{
  "profiles": {
    "glm": {
      "name": "GLM-5.1",
      "alias": "copus",
      ...
    }
  }
}
```

## 配置文件

位置: `~/.claude/profiles/profiles.json`

```json
{
  "current": "glm",
  "profiles": {
    "glm": {
      "name": "GLM-5.1",
      "base_url": "https://open.bigmodel.cn/api/anthropic",
      "api_key": "your-api-key",
      "model": "glm-5.1",
      "alias": "cglm"
    },
    "deepseek": {
      "name": "DeepSeek-v4-pro",
      "base_url": "https://api.deepseek.com",
      "api_key": "your-api-key",
      "model": "deepseek-v4-pro"
    }
  }
}
```

## 原理

每个 alias 展开后：

```bash
alias cglm='ANTHROPIC_BASE_URL="https://..." ANTHROPIC_API_KEY="xxx" ANTHROPIC_MODEL="glm-5.1" claude'
```

环境变量仅在当前 shell 进程生效，不影响 `~/.claude/settings.json`，多窗口完全不冲突。

## 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `CC_PROFILES_DIR` | `~/.claude/profiles` | 配置目录 |
| `CC_PROFS_BIN` | auto-detect | Claude 二进制路径 |

## 使用场景

- 💰 多家模型额度有限，分摊使用
- ⚡ 简单任务用便宜模型，复杂任务用强模型
- 🔀 同一项目多个 Agent 并行工作
- 🧪 A/B 测试不同模型效果

## License

MIT
