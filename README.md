# cc-profiles

> Claude Code 多模型 Profile 管理器 — 不同终端窗口跑不同模型，互不干扰。

`claude --model` 或 `cc switch` 的问题是全局生效，多开就冲突。cc-profiles 通过环境变量隔离，每个 shell 进程独立，真正支持多开。

## ✨ 特性

- 🔄 多模型并行 — 不同终端窗口跑不同模型，互不影响
- 🔌 兼容所有 Anthropic 协议的 API（GLM、DeepSeek、Mimo 等）
- 📋 从现有 `settings.json` 一键同步配置
- 🚀 `cglm` / `cds` / `cmimo` 一键启动
- 💾 API Key 本地存储，不上传

## 安装

```bash
# 克隆
git clone https://github.com/dongdada29/cc-profiles.git
cd cc-profiles

# 加载到 shell（二选一）
# 方式1: source
echo 'source ~/path/to/cc-profiles/cc-profiles.sh' >> ~/.zshrc

# 方式2: symlink 到 PATH（推荐）
ln -s $(pwd)/cc-profiles.sh /usr/local/bin/cc-profiles
# 然后在 .zshrc 里:
echo 'eval "$(cc-profiles aliases)"' >> ~/.zshrc
```

## 快速开始

```bash
# 1. 编辑配置，填入 API Key
cc-profiles edit

# 2. 或者从当前 claude 配置同步
cc-profiles sync

# 3. 启动！
cglm        # GLM-5.1
cds         # DeepSeek-v4-pro
cmimo       # Mimo-v2.5
```

## 命令

```
cc-profiles list              列出所有配置
cc-profiles sync              从 settings.json 同步当前配置
cc-profiles add [name]        交互式添加新模型
cc-profiles remove [name]     删除配置
cc-profiles edit              用 $EDITOR 编辑配置文件
cc-profiles aliases           显示生成的 alias（调试用）
cc-profiles glm              直接启动某个 profile（可带 claude 参数）
```

## 配置文件

位置: `~/.claude/profiles/profiles.json`

```json
{
  "profiles": {
    "glm": {
      "name": "GLM-5.1",
      "base_url": "https://open.bigmodel.cn/api/anthropic",
      "api_key": "your-api-key",
      "model": "glm-5.1"
    },
    "deepseek": {
      "name": "DeepSeek-v4-pro",
      "base_url": "https://api.deepseek.com",
      "api_key": "your-api-key",
      "model": "deepseek-v4-pro"
    },
    "mimo": {
      "name": "Mimo-v2.5",
      "base_url": "https://api.mimo.com/v1",
      "api_key": "your-api-key",
      "model": "mimo-v2.5"
    }
  }
}
```

## 原理

每个 alias 展开后形如：

```bash
alias cglm='ANTHROPIC_BASE_URL="https://open.bigmodel.cn/api/anthropic" ANTHROPIC_API_KEY="xxx" ANTHROPIC_MODEL="glm-5.1" claude'
```

环境变量仅在当前 shell 进程生效，不影响 `~/.claude/settings.json`，多窗口完全不冲突。

## 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `CC_PROFILES_DIR` | `~/.claude/profiles` | 配置目录 |
| `CC_PROFS_BIN` | `claude` | Claude 二进制路径 |

## 使用场景

- 💰 多家模型额度有限，分摊使用
- ⚡ 简单任务用便宜模型，复杂任务用强模型
- 🔀 同一项目多个 Agent 并行工作
- 🧪 A/B 测试不同模型效果

## License

MIT
