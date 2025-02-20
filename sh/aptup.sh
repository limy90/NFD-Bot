#!/bin/bash

# 定义日志文件和版本文件
LOG_FILE="upgrade_log.txt"
PRE_VERSIONS="pre_versions.txt"
POST_VERSIONS="post_versions.txt"
CURRENT_SCRIPT="$(basename "\$0")"

# 检查root权限
if [ "$EUID" -ne 0 ]; then
    echo "请以root用户权限运行此脚本"
    exit 1
fi

# 自动清理函数
auto_clean() {
    # 静默删除所有相关文件
    rm -f "$LOG_FILE" "$PRE_VERSIONS" "$POST_VERSIONS" "$CURRENT_SCRIPT" 2>/dev/null
    exit ${1:-0}  # 默认正常退出
}

# 记录版本信息（使用sed+cut替代awk）
record_versions() {
    dpkg -l | sed -n '/^ii/s/  */ /gp' | cut -d ' ' -f2,3 > "\$1" || return 1
}

# 版本对比函数（带文件存在性检查）
show_changes() {
    [ ! -f "$POST_VERSIONS" ] && return 1
    echo -e "\n版本变化对比："
    while IFS= read -r line; do
        pkg="${line%% *}"
        old_ver=$(grep "^$pkg " "$PRE_VERSIONS" 2>/dev/null | cut -d ' ' -f2)
        new_ver=$(cut -d ' ' -f2 <<< "$line")
        [ -n "$old_ver" ] && [ "$old_ver" != "$new_ver" ] && \
        printf "%-25s %-15s → %s\n" "$pkg" "$old_ver" "$new_ver"
    done < "$POST_VERSIONS"
}

# 主流程
trap 'auto_clean 1' ERR  # 捕获错误时自动清理

# 记录升级前版本
record_versions "$PRE_VERSIONS" || {
    echo "无法记录初始版本信息"
    auto_clean 1
}

# 更新包列表
if ! apt-get update &>> "$LOG_FILE"; then
    echo "更新失败，查看日志: $LOG_FILE"
    auto_clean 1
fi

# 获取可升级包列表
UPGRADE_LIST=$(apt-get upgrade -s | grep '^Inst' | cut -d ' ' -f2 | tr '\n' ' ')
if [ -z "$UPGRADE_LIST" ]; then
    echo "系统已是最新状态，无可用更新"
    auto_clean 0  # 静默清理退出
fi

# 执行升级操作
if ! apt-get dist-upgrade -y &>> "$LOG_FILE"; then
    echo "升级出错，查看日志: $LOG_FILE"
    auto_clean 1
fi

# 记录升级后版本
record_versions "$POST_VERSIONS" || {
    echo "无法记录升级后版本信息"
    auto_clean 1
}

# 显示版本对比
show_changes || echo "未发现版本变化"

# 最终清理（保留日志文件）
rm -f "$PRE_VERSIONS" "$POST_VERSIONS" 2>/dev/null
echo "操作完成，日志文件保留在: $LOG_FILE"
exit 0
