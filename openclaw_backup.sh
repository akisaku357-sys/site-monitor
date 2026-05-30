#!/bin/bash
# ===========================================
# OpenClaw 定时备份脚本 (Mac 优化完美版 + Git 上传 + 通知)
# ===========================================
# 备份策略: 每日备份，保留最近 7 份
# ===========================================

set -euo pipefail

# ========== 显式设置环境变量 (launchd 环境变量问题) ==========
# 显式设置 HOME（即使 launchd 没有提供）
export HOME="/Users/357data"
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
export SHELL="/bin/zsh"

# ========== 配置区域 ==========
# 动态获取家目录，避免硬编码
BACKUP_DIR="${HOME}/OpenClaw_Backups"
OPENCLAW_DATA_DIR="${HOME}/.openclaw"
GIT_REPO_DIR="${HOME}/openclawBK"
KEEP_BACKUPS=7
LOG_FILE="${BACKUP_DIR}/backup.log"

# 文件拆分配置
MAX_FILE_SIZE=$((100 * 1024 * 1024))  # 100MB

# 代理配置
PROXY_PORT=1087
HTTP_PROXY="http://127.0.0.1:${PROXY_PORT}"
HTTPS_PROXY="http://127.0.0.1:${PROXY_PORT}"

# 通知配置 (Bark)
NOTIFICATION_URL="https://api.day.app/D64zprNPpRypHArZ7ykAUT/opeclawbackup"

# ========== 颜色输出 ==========
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ========== 日志函数 (修复颜色污染) ==========
log() {
    local level="$1"
    shift
    local message="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
    # 屏幕输出带颜色到标准错误，避免被变量捕获
    echo -e "$message" >&2
    # 日志文件剔除颜色代码
    echo -e "$message" | sed 's/\x1b\[[0-9;]*m//g' >> "$LOG_FILE"
}

info()    { log "INFO" "${GREEN}$*${NC}"; }
warn()    { log "WARN" "${YELLOW}$*${NC}"; }
error()   { log "ERROR" "${RED}$*${NC}"; }

# ========== 发送通知 ==========
send_notification() {
    local backup_status="$1"
    local git_status="$2"
    local message="备份状态: ${backup_status} | GitHub上传状态: ${git_status}"
    
    info "发送通知: $message"
    
    # 对 URL 进行编码
    local encoded_message
    encoded_message=$(echo -n "$message" | sed 's/ /%20/g' | sed 's/|/%7C/g')
    
    # 使用代理发送通知
    if curl -L -x "$HTTP_PROXY" -s -o /dev/null -w "%{http_code}" "${NOTIFICATION_URL}/${encoded_message}" > /dev/null 2>&1; then
        info "通知发送成功"
    else
        warn "通知发送失败，继续执行..."
    fi
}

# ========== 备份前检查 ==========
pre_backup_check() {
    info "========== 开始备份前检查 =========="
    
    if [ ! -d "$BACKUP_DIR" ]; then
        mkdir -p "$BACKUP_DIR"
        info "创建备份目录: $BACKUP_DIR"
    fi
    
    if ! command -v openclaw &> /dev/null; then
        error "openclaw 未安装或不在 PATH 中"
        send_notification "失败" "未执行"
        exit 1
    fi
    
    if [ ! -d "$OPENCLAW_DATA_DIR" ]; then
        error "数据目录不存在: $OPENCLAW_DATA_DIR"
        send_notification "失败" "未执行"
        exit 1
    fi
    
    if [ ! -d "$GIT_REPO_DIR" ]; then
        error "Git 仓库目录不存在: $GIT_REPO_DIR"
        error "请先确保 git 仓库已正确设置"
        send_notification "失败" "未执行"
        exit 1
    fi
    
    if pgrep -f "openclaw gateway" > /dev/null 2>&1; then
        info "检测到 OpenClaw 网关正在运行，尝试停止..."
        openclaw gateway stop
        
        sleep 5
        
        if pgrep -f "openclaw gateway" > /dev/null 2>&1; then
            error "无法停止 OpenClaw 网关，请手动停止后重试"
            send_notification "失败" "未执行"
            exit 1
        fi
        info "网关已成功停止"
    else
        info "网关未运行，无需停止"
    fi
    
    info "========== 备份前检查完成 =========="
}

# ========== 执行备份 ==========
perform_backup() {
    info "========== 开始执行备份 =========="
    
    local timestamp
    timestamp=$(date '+%Y%m%d_%H%M%S')
    local backup_file="${BACKUP_DIR}/openclaw_backup_${timestamp}.tar.gz"
    local metadata_file="${BACKUP_DIR}/openclaw_backup_${timestamp}.meta"
    
    info "正在打包数据目录: $OPENCLAW_DATA_DIR"
    # 全量备份：备份所有内容
    if tar -czf "$backup_file" \
        -C "$(dirname "$OPENCLAW_DATA_DIR")" \
        "$(basename "$OPENCLAW_DATA_DIR")" \
        >> "$LOG_FILE" 2>&1; then
        info "数据目录打包完成: $backup_file"
    else
        error "数据目录打包失败"
        send_notification "失败" "未执行"
        exit 1
    fi
    
    cat > "$metadata_file" << EOF
Backup Metadata
===============
Backup Date: $(date '+%Y-%m-%d %H:%M:%S')
Hostname: $(hostname)
Username: $(whoami)
OpenClaw Version: $(openclaw --version 2>/dev/null || echo "unknown")
Data Directory: $OPENCLAW_DATA_DIR"
Backup Size: $(du -h "$backup_file" | cut -f1)
Backup File: $backup_file"
EOF
    info "元数据文件已创建: $metadata_file"
    
    local file_size
    file_size=$(stat -f%z "$backup_file" 2>/dev/null || stat -c%s "$backup_file" 2>/dev/null)
    if [ "$file_size" -lt 1024 ]; then
        error "备份文件异常: 文件大小只有 $file_size 字节"
        warn "请检查 Mac 系统设置 -> 隐私与安全性 -> 完全磁盘访问权限"
        send_notification "失败" "未执行"
        exit 1
    fi
    info "备份文件验证通过: $(du -h "$backup_file" | cut -f1)"
    
    # 检查并拆分大文件
    split_large_file "$backup_file"
    
    # 修复：采用官方标准方式拉起网关进程
    info "正在重新启动网关..."
    openclaw gateway start >> "$LOG_FILE" 2>&1
    sleep 3
    
    if pgrep -f "openclaw gateway" > /dev/null 2>&1; then
        info "网关已成功启动"
    else
        warn "网关自动启动可能失败，请手动检查: openclaw gateway status"
    fi
    
    info "========== 备份完成 =========="
}

# ========== 拆分大文件（>100MB） ==========
split_large_file() {
    local file="$1"
    
    if [ ! -f "$file" ]; then
        error "文件不存在: $file"
        return 1
    fi
    
    local file_size
    file_size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null)
    
    if [ "$file_size" -le "$MAX_FILE_SIZE" ]; then
        info "文件大小 $(du -h "$file" | cut -f1) 未超过限制，无需拆分"
        return 0
    fi
    
    info "文件大小 $(du -h "$file" | cut -f1) 超过限制，开始拆分..."
    
    local base_name="${file%.tar.gz}"
    local split_prefix="${base_name}_part"
    
    # 使用 split 命令拆分文件
    if split -b "${MAX_FILE_SIZE}" "$file" "$split_prefix"; then
        info "文件拆分完成"
        
        # 更新元数据，记录拆分信息
        local metadata_file="${base_name}.meta"
        local part_count=$(ls "${split_prefix}"* 2>/dev/null | wc -l)
        
        # 追加拆分信息到元数据
        cat >> "$metadata_file" << EOF

Split Information
=================
Original File: $(basename "$file")
Original Size: $(du -h "$file" | cut -f1)
Split Parts: $part_count
Split Prefix: $(basename "$split_prefix")
EOF
        
        # 删除原始文件，只保留拆分后的部分
        rm -f "$file"
        info "已删除原始文件，保留拆分后的 $part_count 个部分"
        
        return 0
    else
        error "文件拆分失败"
        return 1
    fi
}

# ========== 合并拆分的文件（用于恢复） ==========
merge_split_files() {
    local base_name="$1"
    
    # 查找所有拆分文件
    local split_files=("${base_name}_part"*)
    
    if [ ${#split_files[@]} -eq 0 ]; then
        error "未找到拆分文件"
        return 1
    fi
    
    info "找到 ${#split_files[@]} 个拆分部分，开始合并..."
    
    # 按顺序合并
    if cat "${split_files[@]}" > "${base_name}.tar.gz"; then
        info "文件合并完成"
        return 0
    else
        error "文件合并失败"
        return 1
    fi
}

# ========== 复制到 Git 仓库 ==========
copy_to_git_repo() {
    info "========== 复制文件到 Git 仓库 =========="
    
    # 找到最新的备份文件（单个 tar.gz）
    local latest_backup
    latest_backup=$(ls -t "${BACKUP_DIR}"/openclaw_backup_*.tar.gz 2>/dev/null | head -n 1)
    
    if [ -z "$latest_backup" ]; then
        error "未找到备份文件"
        return 1
    fi
    
    local latest_timestamp
    latest_timestamp=$(basename "$latest_backup" | sed -E 's/openclaw_backup_([0-9]{8}_[0-9]{6})\.tar\.gz/\1/')
    local base_name="${BACKUP_DIR}/openclaw_backup_${latest_timestamp}"
    local latest_meta="${base_name}.meta"
    
    info "最新备份: $(basename "$latest_backup")"
    info "最新备份时间戳: $latest_timestamp"
    
    # 复制文件
    cp "$latest_backup" "$GIT_REPO_DIR/"
    [ -f "$latest_meta" ] && cp "$latest_meta" "$GIT_REPO_DIR/"
    cp "$0" "$GIT_REPO_DIR/"
    
    info "文件已复制到 Git 仓库"
    info "========== 复制完成 =========="
}

# ========== Git 上传 ==========
git_upload() {
    info "========== 开始 Git 上传 =========="
    
    cd "$GIT_REPO_DIR"
    
    # 设置代理
    export http_proxy="$HTTP_PROXY"
    export https_proxy="$HTTPS_PROXY"
    git config --local http.proxy "$HTTP_PROXY"
    git config --local https.proxy "$HTTPS_PROXY"
    
    # 确保使用 gh 认证
    if command -v gh &> /dev/null; then
        gh auth setup-git > /dev/null 2>&1
    fi
    
    # Git 操作
    git add . >> "$LOG_FILE" 2>&1
    
    local git_status="成功"
    if git commit -m "Update: OpenClaw backup $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE" 2>&1; then
        info "Git commit 成功"
    else
        warn "Git commit 失败或无更改"
        git_status="无更改"
    fi
    
    if git push -u origin main >> "$LOG_FILE" 2>&1; then
        info "Git push 成功"
    else
        error "Git push 失败"
        git_status="失败"
    fi
    
    info "========== Git 上传完成 =========="
    
    # 只返回状态，通过标准输出返回
    echo "$git_status"
}

# ========== 清理旧备份（本地保留 7 份，GitHub 保留全部） ==========
cleanup_old_backups() {
    info "========== 清理旧备份 =========="
    
    # 获取所有备份的时间戳（包括拆分的）
    local all_timestamps
    all_timestamps=$(find "$BACKUP_DIR" \( -name "openclaw_backup_*.tar.gz" -o -name "openclaw_backup_*_part*" \) -type f -print0 | \
        xargs -0 -n1 basename | \
        sed -E 's/openclaw_backup_([0-9]{8}_[0-9]{6}).*/\1/' | \
        sort -u | \
        sort -r)
    
    # 转换为数组
    local -a timestamp_array=($all_timestamps)
    
    local deleted_count=0
    local total_timestamps=${#timestamp_array[@]}
    
    # 保留最新的 KEEP_BACKUPS 份，删除其余的
    if [ "$total_timestamps" -gt "$KEEP_BACKUPS" ]; then
        local timestamps_to_delete=("${timestamp_array[@]:$KEEP_BACKUPS}")
        
        for ts in "${timestamps_to_delete[@]}"; do
            local base_name="${BACKUP_DIR}/openclaw_backup_${ts}"
            
            # 删除主文件（如果存在）
            if [ -f "${base_name}.tar.gz" ]; then
                rm -f "${base_name}.tar.gz"
                info "删除本地旧备份: openclaw_backup_${ts}.tar.gz"
            fi
            
            # 删除拆分文件（如果存在）
            local split_files=("${base_name}_part"*)
            if [ ${#split_files[@]} -gt 0 ]; then
                rm -f "${split_files[@]}"
                info "删除本地旧备份（拆分）: ${#split_files[@]} 个文件"
            fi
            
            # 删除元数据文件
            rm -f "${base_name}.meta"
            
            deleted_count=$((deleted_count + 1))
        done
    fi
    
    # GitHub 仓库 - 保留所有备份，不清理
    local git_backup_count
    git_backup_count=$(find "$GIT_REPO_DIR" \( -name "openclaw_backup_*.tar.gz" -o -name "openclaw_backup_*_part*" \) -type f 2>/dev/null | wc -l)
    
    # 统计剩余备份数
    local remaining_count
    remaining_count=$(find "$BACKUP_DIR" \( -name "openclaw_backup_*.tar.gz" -o -name "openclaw_backup_*_part*" \) -type f -print0 | \
        xargs -0 -n1 basename | \
        sed -E 's/openclaw_backup_([0-9]{8}_[0-9]{6}).*/\1/' | \
        sort -u | \
        wc -l)
    
    info "本地备份: 已删除 $deleted_count 个，保留 $remaining_count 个"
    info "GitHub 备份: 保留全部 $git_backup_count 个（不清理）"
    info "========== 清理完成 =========="
}

# ========== 显示备份统计 ==========
show_backup_stats() {
    info "========== 备份统计 =========="
    info "备份目录: $BACKUP_DIR"
    info "Git 仓库: $GIT_REPO_DIR"
    info "保留策略: 最近 $KEEP_BACKUPS 份"
    
    # 获取所有备份的时间戳
    local all_timestamps
    all_timestamps=$(find "$BACKUP_DIR" \( -name "openclaw_backup_*.tar.gz" -o -name "openclaw_backup_*_part*" \) -type f -print0 | \
        xargs -0 -n1 basename | \
        sed -E 's/openclaw_backup_([0-9]{8}_[0-9]{6}).*/\1/' | \
        sort -u | \
        sort -r)
    
    local -a timestamp_array=($all_timestamps)
    info "总备份数量: ${#timestamp_array[@]}"
    
    if [ "${#timestamp_array[@]}" -gt 0 ]; then
        info "备份列表:"
        for ts in "${timestamp_array[@]}"; do
            local base_name="${BACKUP_DIR}/openclaw_backup_${ts}"
            
            if [ -f "${base_name}.tar.gz" ]; then
                # 单个文件
                local file_size=$(du -h "${base_name}.tar.gz" | cut -f1)
                info "  - openclaw_backup_${ts}.tar.gz ($file_size)"
            else
                # 拆分的文件
                local part_files=("${base_name}_part"*)
                local total_size=$(du -ch "${part_files[@]}" 2>/dev/null | tail -n1 | cut -f1)
                info "  - openclaw_backup_${ts} (${#part_files[@]} 部分, ${total_size})"
            fi
        done
    fi
    
    local total_size
    total_size=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)
    info "备份总大小: $total_size"
    info "========== 统计完成 =========="
}

# ========== 主函数 ==========
main() {
    local backup_status="成功"
    local git_status="未执行"
    
    case "${1:-all}" in
        all)
            if pre_backup_check; then
                if perform_backup; then
                    if copy_to_git_repo; then
                        # 使用临时文件捕获 git 状态
                        local temp_file
                        temp_file=$(mktemp)
                        git_upload > "$temp_file"
                        git_status=$(cat "$temp_file")
                        rm -f "$temp_file"
                    else
                        git_status="复制失败"
                    fi
                    cleanup_old_backups
                    show_backup_stats
                else
                    backup_status="失败"
                fi
            else
                backup_status="失败"
            fi
            
            # 发送通知
            send_notification "$backup_status" "$git_status"
            ;;
        check) pre_backup_check ;;
        backup) 
            pre_backup_check
            perform_backup
            ;;
        git-upload)
            copy_to_git_repo
            # 使用临时文件捕获 git 状态
            local temp_file
            temp_file=$(mktemp)
            git_upload > "$temp_file"
            git_status=$(cat "$temp_file")
            rm -f "$temp_file"
            send_notification "已完成" "$git_status"
            ;;
        cleanup) cleanup_old_backups ;;
        stats) show_backup_stats ;;
        restore)
            if [ $# -lt 2 ]; then
                error "恢复操作需要指定备份时间戳！"
                error "用法: $0 restore <备份时间戳>"
                error "示例: $0 restore 20260528_084201"
                info ""
                info "可用备份列表:"
                find "$BACKUP_DIR" -name "openclaw_backup_*.tar.gz" -o -name "openclaw_backup_*_part*" -type f | \
                    sed -E 's/.*openclaw_backup_([0-9]{8}_[0-9]{6}).*/  - \1/' | \
                    sort -u
                exit 1
            fi
            
            local restore_timestamp="$2"
            local restore_base="${BACKUP_DIR}/openclaw_backup_${restore_timestamp}"
            local restore_file="${restore_base}.tar.gz"
            
            # 检查是否需要合并
            if [ ! -f "$restore_file" ] && [ -f "${restore_base}_partaa" ]; then
                info "检测到拆分的备份文件，正在合并..."
                if ! merge_split_files "$restore_base"; then
                    error "文件合并失败"
                    exit 1
                fi
                info "合并完成"
            fi
            
            # 检查恢复文件是否存在
            if [ ! -f "$restore_file" ]; then
                error "备份文件不存在: $restore_file"
                info ""
                info "请先从 GitHub 拉取备份："
                info "  cd $GIT_REPO_DIR && git pull"
                info ""
                info "然后将备份复制到本地："
                info "  cp $GIT_REPO_DIR/openclaw_backup_${restore_timestamp}.tar.gz $BACKUP_DIR/"
                exit 1
            fi
            
            info "========== 开始恢复备份 =========="
            info "备份文件: $restore_file"
            info "文件大小: $(du -h "$restore_file" | cut -f1)"
            info ""
            
            # 停止网关
            info "停止网关..."
            if pgrep -f "openclaw gateway" > /dev/null 2>&1; then
                openclaw gateway stop
                sleep 2
            fi
            
            # 执行恢复（使用 tar 解压）
            info "执行恢复（解压备份）..."
            cd "$HOME"
            
            # 完全恢复模式：先删除旧目录，再解压
            info "完全恢复模式：正在删除旧的 .openclaw 目录..."
            rm -rf "$OPENCLAW_DATA_DIR"
            info "旧目录已删除"
            
            if tar -xzf "$restore_file"; then
                info "备份已解压到 ~/.openclaw/"
                info "完全恢复成功！"
            else
                error "恢复失败，请检查错误信息"
                exit 1
            fi
            
            # 重启网关
            info "重启网关..."
            openclaw gateway start
            sleep 3
            
            # 验证恢复
            if pgrep -f "openclaw gateway" > /dev/null 2>&1; then
                info "网关已成功启动"
            else
                warn "网关启动可能失败，请重启 Mac 或手动运行: openclaw gateway start"
            fi
            
            info "========== 恢复完成 =========="
            info ""
            info "如果网关启动失败，请重启 Mac！"
            exit 0
            ;;
        *)
            echo "用法: $0 {all|check|backup|git-upload|cleanup|stats|restore}"
            exit 1
            ;;
    esac
}

main "$@"
