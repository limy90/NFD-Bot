#!/bin/bash

# 定义日志文件
LOG_FILE="upgrade_log.txt"

# 检查是否以root用户运行
if [ "$EUID" -ne 0 ]; then
    echo "请以root用户权限运行此脚本。"
    exit 1
fi

echo "正在检查更新并更新包列表..."
if ! apt-get update >> "$LOG_FILE" 2>&1; then
    echo "失败，请检查日志：$LOG_FILE"
    exit 1
fi

echo "获取可升级的包信息..."
# 列出所有可升级的包，并重定向错误输出
UPGRADE_INFO=$(apt-get upgrade --dry-run | grep -o '^[^ ]*' | tail -n +2)

if [ -z "$UPGRADE_INFO" ]; then
    echo "没有可用的更新。"
    exit 0
else
    echo "检测到可升级的软件包，正在开始升级..."
fi

# 执行升级操作
echo "开始升级..." | tee -a "$LOG_FILE"
if ! apt-get dist-upgrade -y >> "$LOG_FILE" 2>&1; then
    echo "升级过程中出现错误，请检查日志：$LOG_FILE"
    exit 1
fi

echo "分析升级结果..." | tee -a "$LOG_FILE"
# 使用apt-get upgrade --dry-run来获取待升级包的信息
待升级包数量=$(apt-get upgrade --dry-run | grep -o '^[^ ]*' | tail -n +2 | wc -l)
已升级包数量=$(grep "升级了" "$LOG_FILE" | wc -l)
升级失败包数量=$(grep -E "无法安装|依赖问题" "$LOG_FILE" | wc -l)

echo -e "\n升级结果统计："
echo "待升级包数：$待升级包数量 个"
echo "已成功升级包数：$已升级包数量 个"
echo "升级失败包数：$升级失败包数量 个"

# 显示升级日志
echo -e "\n完整的升级日志如下："
cat "$LOG_FILE"

# 提示用户是否删除脚本和日志文件
read -p "升级完成。是否删除此脚本和升级日志？(y/n) " DELETE

if [ "$DELETE" = "y" ] || [ "$DELETE" = "Y" ]; then
    # 删除脚本和日志文件
    echo "删除脚本和日志文件..."
    rm "$0" && rm "$LOG_FILE"
    echo "脚本和日志文件已删除。"
else
    echo "保留脚本和日志文件。"
fi

echo "脚本完成。"
exit 0
