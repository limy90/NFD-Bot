#!/bin/bash

# 定义固定存储路径
ROOT_DIR="/root"
SCRIPT_NAME="aptup.sh"
TIMESTAMP=$(date +%Y%m%d%H%M%S)
LOG_FILE="${ROOT_DIR}/upgrade_${TIMESTAMP}.log"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # 无颜色

# 初始化计数器
SUCCESS_COUNT=0
FAIL_COUNT=0

# 检查root权限
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}错误：本脚本需要root权限执行${NC}" | tee -a "$LOG_FILE"
    exit 1
fi

# 记录所有输出到日志文件
exec > >(tee -a "$LOG_FILE")
exec 2>&1

# 获取可升级包数量
echo -e "${YELLOW}正在检查可升级软件包...${NC}"
UPGRADABLE_COUNT=$(apt list --upgradable 2>/dev/null | grep -v "^Listing" | wc -l)

if [ $UPGRADABLE_COUNT -eq 0 ]; then
    echo -e "${GREEN}没有需要升级的软件包${NC}"
    echo "正在删除脚本和日志..."
    rm -f "${ROOT_DIR}/${SCRIPT_NAME}" "$LOG_FILE"
    exit 0
fi

# 用户确认提示
echo -e "${YELLOW}检测到 ${UPGRADABLE_COUNT} 个可升级软件包${NC}"
read -p "是否要执行升级？[Y/n] " -n 1 -r
echo
if [[ $REPLY =~ ^[Nn]$ ]]; then
    exit 0
fi

# 执行升级操作
perform_upgrade() {
    local output
    output=$(apt-get "$@" -y 2>&1)
    local exit_code=$?
    
    echo "$output"
    
    # 解析成功数量
    local upgraded=$(echo "$output" | grep -oP '\d+(?= upgraded)' | awk '{sum+=\$1} END{print sum}')
    [ -z "$upgraded" ] && upgraded=0
    
    # 记录失败次数
    if [ $exit_code -ne 0 ]; then
        FAIL_COUNT=$((FAIL_COUNT + 1))
    else
        SUCCESS_COUNT=$((SUCCESS_COUNT + upgraded))
    fi
}

# 执行升级流程
echo -e "${YELLOW}\n正在更新软件包列表...${NC}"
apt-get update || FAIL_COUNT=$((FAIL_COUNT + 1))

echo -e "${YELLOW}\n正在执行标准升级...${NC}"
perform_upgrade upgrade

echo -e "${YELLOW}\n正在执行深度升级...${NC}"
perform_upgrade dist-upgrade

# 清理旧包
echo -e "${YELLOW}\n清理不需要的软件包...${NC}"
apt-get autoremove -y
apt-get autoclean

# 显示统计结果
echo -e "\n${GREEN}升级完成！${NC}"
echo -e "成功升级软件包: ${SUCCESS_COUNT} 个"
echo -e "遇到错误次数:    ${FAIL_COUNT} 次"
echo -e "日志文件路径:    ${LOG_FILE}"

# 重启检测
if [ -f "/var/run/reboot-required" ]; then
    echo -e "${RED}\n系统需要重启！执行命令: sudo reboot${NC}"
fi

# 清理确认（仅在/root目录下操作）
read -p "是否要删除本脚本和日志文件？[y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "正在删除..."
    rm -f "${ROOT_DIR}/${SCRIPT_NAME}" "$LOG_FILE"
fi
