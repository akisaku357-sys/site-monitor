# OpenClaw 备份仓库

这个仓库包含 OpenClaw 的备份文件和备份脚本。

## 功能特性

✅ **自动备份** - 全量完整备份 OpenClaw 数据
✅ **Git 上传** - 每次备份自动推送到 GitHub
✅ **代理支持** - 使用 1087 端口代理
✅ **备份保留** - 本地保留 7 份，GitHub 保留全部
✅ **状态通知** - 通过 Bark 推送备份和上传状态
✅ **网关管理** - 自动停止和重启网关
✅ **大文件拆分** - 超过 100MB 自动拆分成多个小文件
✅ **自动合并** - 恢复时自动合并拆分的文件
✅ **完全恢复** - 恢复时先删除旧目录，再解压备份
✅ **完整统计** - 显示所有备份的详细信息

## 备份文件列表

最新备份会显示在这里，请运行 `./openclaw_backup.sh stats` 查看完整列表。

## 备份脚本

- `openclaw_backup.sh` - 增强版备份脚本（含 Git 上传和通知）

## 快速使用指南

### 完整备份（推荐）
```bash
./openclaw_backup.sh all
```
执行完整流程：备份前检查 → 执行备份 → Git 上传 → 清理旧备份 → 发送通知

### 其他命令
```bash
./openclaw_backup.sh check      # 备份前检查
./openclaw_backup.sh backup     # 仅执行备份
./openclaw_backup.sh git-upload # 仅 Git 上传
./openclaw_backup.sh cleanup    # 清理旧备份
./openclaw_backup.sh stats      # 查看备份统计
./openclaw_backup.sh restore    # 恢复操作
```

### 恢复备份

#### 方法一：使用脚本恢复（推荐）
```bash
# 1. 先查看可用备份
./openclaw_backup.sh restore

# 2. 恢复指定备份
./openclaw_backup.sh restore 20260529_030000

# 脚本会自动：
# 1. 停止网关
# 2. 删除旧的 ~/.openclaw 目录（完全恢复模式）
# 3. 解压备份到 ~/.openclaw/
# 4. 尝试重启网关
```

#### 方法二：手动恢复
```bash
# 1. 停止网关
openclaw gateway stop

# 2. 删除旧目录（完全恢复）
rm -rf ~/.openclaw

# 3. 解压备份
cd ~
tar -xzf ~/OpenClaw_Backups/openclaw_backup_YYYYMMDD_HHMMSS.tar.gz

# 4. 重启网关（如果失败，请重启 Mac）
openclaw gateway start
```

### 查看可用备份
```bash
./openclaw_backup.sh restore
# 会列出所有可用的备份时间戳
```

### 从 GitHub 恢复（如果本地没有备份）
```bash
# 1. 拉取最新备份
cd ~/openclawBK && git pull

# 2. 复制备份到本地
cp ~/openclawBK/openclaw_backup_YYYYMMDD_HHMMSS.tar.gz ~/OpenClaw_Backups/

# 3. 使用脚本恢复
./openclaw_backup.sh restore YYYYMMDD_HHMMSS
```

## 配置说明

### 代理配置
脚本默认使用本地 1087 端口代理：
```bash
PROXY_PORT=1087
HTTP_PROXY="http://127.0.0.1:1087"
HTTPS_PROXY="http://127.0.0.1:1087"
```

### 通知配置
使用 Bark 推送通知，配置在脚本中：
```bash
NOTIFICATION_URL="https://api.day.app/D64zprNPpRypHArZ7ykAUT/opeclawbackup"
```

### 保留策略
- 本地备份：保留最近 **7 份**
- GitHub 备份：**保留全部**（不清理）

## 定时任务设置

### 使用 launchd (Mac 推荐)
配置文件位置：`~/Library/LaunchAgents/com.openclaw.backup.plist`

执行时间：**每周六凌晨 3:00**

```bash
# 加载任务
launchctl load ~/Library/LaunchAgents/com.openclaw.backup.plist

# 卸载任务
launchctl unload ~/Library/LaunchAgents/com.openclaw.backup.plist

# 查看任务状态
launchctl list | grep openclaw
```

## 目录结构

```
~/.openclaw/              # OpenClaw 数据目录
~/OpenClaw_Backups/       # 本地备份目录
  ├── backup.log          # 备份日志
  ├── openclaw_backup_*.tar.gz           # 小备份（<100MB）
  ├── openclaw_backup_*_part*           # 大备份拆分文件（>100MB）
  └── openclaw_backup_*.meta            # 备份元数据
~/openclawBK/             # Git 仓库目录
  ├── README.md
  ├── openclaw_backup.sh
  ├── openclaw_backup_*.tar.gz           # 备份文件
  ├── openclaw_backup_*_part*           # 拆分文件
  └── openclaw_backup_*.meta            # 元数据
```

## 大文件拆分说明

为了确保备份文件能成功上传到 GitHub，**超过 100MB 的文件会自动拆分成多个小文件**。

### 拆分规则
- 单个文件最大 100MB
- 命名格式：`openclaw_backup_YYYYMMDD_HHMMSS_partaa`, `_partab`, ...
- 元数据文件（.meta）记录拆分信息

### 恢复时自动合并
使用 `restore` 命令时，脚本会自动：
1. 检测是否为拆分文件
2. 自动合并所有部分
3. 执行恢复操作

### 手动合并（如需要）
```bash
# 查看拆分文件
ls openclaw_backup_20260528_124139_part*

# 合并文件
cat openclaw_backup_20260528_124139_part* > openclaw_backup_20260528_124139.tar.gz
```

## 注意事项

⚠️ 此仓库包含敏感数据，保持私有！
⚠️ 确保代理 1087 端口正常工作
⚠️ 确保 GitHub CLI 已认证（gh auth login）
⚠️ Mac 用户需要给终端完全磁盘访问权限
⚠️ 超过 100MB 的备份会自动拆分，这是正常现象
⚠️ 如果网关启动失败，请**重启 Mac**，系统会自动加载网关服务

---
Created: 2026-05-27
Updated: 2026-05-30 (全量备份 + 完全恢复模式 + 每周六定时)
