#!/bin/bash

# 定义日志文件和时间戳
LOG_FILE="upgrade_log_$(date +%Y%m%d%H%M).txt"
TimeStamp=$(date +%Y-%m-%d_%H:%M:%S)

# 添加颜色输出以提高可读性
RED='\033[031m'
GREEN='\033[0;32m'
BLUE='\033[0;34'
NC='\033[0m'

# 检查是否以root用户运行
echo -e "\n${BLUE}[$TimeStamp] 检查权限...${NC}"
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}错误：请以root用户权限运行此脚本！${NC}"
    exit 1
fi

# 创建日志文件并写入初始信息
echo -e "[$TimeStamp] 脚本开始执行。" > "$LOG_FILE"
echo -e "[$TimeStamp] 使用的LOG_FILE: $LOG_FILE" >> "$LOG_FILE"

# 检查系统更新
echo -e "\n${BLUE}[$TimeStamp] 正在检查更新并更新包...${NC}"
if ! apt-get update >> "$LOG_FILE" 2>&1; then
    echo -e "\n${RED}错误：更新包列表失败，请检查日志文件：$LOG_FILE${NC}"
    exit 1
fi

# 获取可升级的包信息
echo -e "\n${BLUE}[$TimeStamp] 获取可升级的包信息...${NC}"
UPGRADE=$(apt-get upgrade --dry-run | awk '/^[^ ]/ {print $1}' | tail -n +2)

if [ -z "$UPGRADE_INFO" ]; then
    echo -e "\n${BLUE}[$TimeStamp] 检查结果：没有可用的更新。脚本结束。${NC}"
    exit 0
else
    echo -e "\n${GREEN}[$TimeStamp] 检测到可升级的软件包，正在开始升级...${NC}"
fi

# 询问用户是否确认升级
read -p "[$TimeStamp] 即将执行升级，继续吗？(Y/n) " CONFIRM
if [ "$CONFIRM" != "Y" ] && [ "$CONFIRM" != "y" ]; then
    echo -e "\n${BLUE}[$TimeStamp] 用户取消，脚本结束。${NC}"
    exit 0
fi

# 执行升级操作
echo -e "\n${BLUE}[$TimeStamp] 开始升级...${NC}" | tee -a "$LOG_FILE"

# 尝试升级
if ! apt-get dist-upgrade -y >> "$LOG_FILE" 2>&1; then
    echo -e "\n${RED}错误：升级过程中出现错误，尝试修复...${NC}" | tee -a "$LOG_FILE"
    
    # 尝试回滚
    echo -e "\n尝试回滚到上一个状态..." | tee -a "$LOG_FILE"
    if apt-get --rollback >> "$LOG_FILE" 2>&1; then
        echo -e "\n${GREEN}回滚成功，系统已回到升级前的状态。${NC}" | tee -a "$LOG_FILE"
    else
        echo -e "\nRED}回滚失败！尝试修复配置问题..." | tee -a "$LOG_FILE"
        # 手动修复配置
        dpkg --configure -a >> "$LOG_FILE" 2>&1
        if [ $? -eq 0 ]; then
            echo -e "\n${GREEN}修复成功，请继续检查系统状态。${NC}" | tee -a "$LOG_FILE"
        else
            echo -e "\n${RED}无法修复配置问题，请手动检查！${NC}" | tee -a "$LOG"
        fi
    fi
    
    exit 1
fi

# 分析升级结果
echo -e "\n${BLUE}[$TimeStamp] 分析升级结果...${NC}" | tee -a "$LOG_FILE"

# 重新获取升级信息
UPGRADE_INFO=$(apt-get upgrade --dry-run | awk '/^[^ ]/ {print $1}' | tail -n +2)
upgrade_packages=$(echo "$UPGRADE_INFO" | wc -l)
successful_upgrades=$(grep -o "升级了 [0-9]+"LOG_FILE" | awk '{sum += $2} END {print sum}')
failed_upgrades=$(grep -E "无法安装|依赖问题" "$LOG_FILE" | wc -l)

echo -e "\升级结果统计："
echo -e "待升级包数：$upgrade_packages 个"
echo -e "已成功升级包数：$successful_upgrades 个"
echo -e "升级失败包数：$failed_upgrades 个"

# 显示升级日志
echo -e "\n完整的升级日志如下："
cat "$LOG_FILE"

# 提示用户是否删除脚本和日志文件
read -p "[$TimeStamp] 升级完成。是否删除此脚本和升级日志？(Y/n) " DELETE

if [ "$DELETE" = "Y" ] || [ "$DELETE" = "y" ]; then
    echo -e "\n${BLUE}[$TimeStamp] 删除脚本和日志文件...${NC}"
    if rm "$0" && rm "$LOG_FILE"; then
        echo -e "\n${GREEN}[$TimeStamp] 脚本和日志文件已删除。${NC}"
    else
        echo -e "\n${RED}错误：删除文件时出现问题。${NC}"
    fi
else
    echo -e "\n${BLUE}[$TimeStamp] 保留脚本和日志文件。${NC}"
fi

echo -e "\n${BLUE}[$TimeStamp] 脚本完成。${NC}"
exit 0
