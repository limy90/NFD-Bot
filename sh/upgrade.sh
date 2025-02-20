#!/bin/bash

# ---------- 配置区 ----------
LOG_FILE="/var/log/upgrade_$(date +%Y%m%d%H%M).log"  # 带时间戳的日志路径
UPGRADE_MODE="upgrade"  # 可选 upgrade/dist-upgrade
USE_APT="yes"           # 使用 apt 替代 apt-get（更友好进度条）
# ---------------------------

# 检查 root 权限
if [ "$EUID" -ne 0 ]; then
    echo -e "\033[31m错误：请以 root 权限运行此脚本\033[0m" >&2
    exit 1
fi

# 记录日志函数
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] \$1" | tee -a "$LOG_FILE"
}

# 清理临时文件
cleanup() {
    if [ -f /tmp/upgradable_pkgs.txt ]; then
        rm /tmp/upgradable_pkgs.txt
    fi
}
trap cleanup EXIT

# 步骤 1: 更新包列表
log "开始更新软件包列表..."
if ! $cmd update >> "$LOG_FILE" 2>&1; then
    log "\033[31m错误：更新包列表失败，请检查日志 $LOG_FILE\033[0m"
    exit 1
fi

# 步骤 2: 获取可升级包（更可靠的方式）
log "检测可升级软件包..."
if [ "$USE_APT" = "yes" ]; then
    cmd=apt
else
    cmd=apt-get
fi

# 使用 apt list --upgradable 获取更清晰的输出
$cmd list --upgradable 2>/dev/null | grep -v "^正在" | awk -F/ '{print \$1}' > /tmp/upgradable_pkgs.txt
UPGRADE_INFO=$(cat /tmp/upgradable_pkgs.txt)

if [ -z "$UPGRADE_INFO" ]; then
    log "没有可用的更新。"
    exit 0
else
    log "检测到以下可升级包：\n$(cat /tmp/upgradable_pkgs.txt)"
fi

# 步骤 3: 执行升级
log "开始升级操作 ($UPGRADE_MODE)..."
if ! $cmd $UPGRADE_MODE -y >> "$LOG_FILE" 2>&1; then
    log "\033[31m错误：升级过程中出现依赖问题，请检查日志 $LOG_FILE\033[0m"
    exit 1
fi

# 步骤 4: 精确统计结果（兼容多语言环境）
成功升级数=$(grep -oP "^\d+ packages? upgraded" "$LOG_FILE" | awk '{print \$1}')
失败数=$(grep -ciE "无法安装|E: |W: 依赖问题" "$LOG_FILE")
待升级数=$(wc -l < /tmp/upgradable_pkgs.txt)

# 步骤 5: 生成报告
log "生成升级报告..."
echo -e "\n\033[34m=== 升级结果统计 ===\033[0m"
echo -e "可升级包总数：\033[33m$待升级数\033[0m"
echo -e "成功升级数：\033[32m$成功升级数\033[0m"
echo -e "失败/警告数：\033[31m$失败数\033[0m"

# 步骤 6: 安全删除确认
if [ $失败数 -gt 0 ]; then
    log "\033[31m警告：存在未解决的依赖或错误，建议手动检查！\033[0m"
fi

read -p "是否删除脚本和日志？(y/N) " DELETE
DELETE=${DELETE:-N}  # 默认值为 N

if [[ $DELETE =~ [yY] ]]; then
    log "正在删除脚本和日志..."
    script_name=$(basename "\$0")
    rm -f "$script_name" "$LOG_FILE"
else
    log "保留脚本和日志：$LOG_FILE"
fi

log "操作完成。建议执行 reboot 重启系统（如需内核更新）。"
exit 0
