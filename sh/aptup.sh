#!/bin/bash

ROOT_DIR="/root"
SCRIPT_NAME="aptup.sh"
TIMESTAMP=$(date +%Y%m%d%H%M%S)
LOG_FILE="${ROOT_DIR}/upgrade_${TIMESTAMP}.log"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SUCCESS_COUNT=0
FAIL_COUNT=0

# 进度显示函数
progress_handler() {
    while IFS= read -r line; do
        # 在终端显示带颜色的状态信息（stderr）
        if [[ "$line" =~ ^Unpacking\ ([^[:space:]]+) ]]; then
            echo -e "${GREEN}▷ 正在解包: ${BASH_REMATCH[1]}${NC}" >&2
        elif [[ "$line" =~ ^Setting\ up\ ([^[:space:]]+) ]]; then
            echo -e "${GREEN}▶ 正在安装: ${BASH_REMATCH[1]}${NC}" >&2
            echo $((++count)) > "$counter_file"
        elif [[ "$line" =~ ^(E:|错误：) ]]; then
            echo -e "${RED}✖ 错误: ${line#* }${NC}" >&2
        elif [[ "$line" =~ ^(Get:|Ign:|Hit:) ]]; then
            echo -e "${YELLOW}ℹ ${line}${NC}" >&2
        fi
        # 原始输出仍通过tee写入日志
        echo "$line"
    done
}

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}错误：本脚本需要root权限执行${NC}" | tee -a "$LOG_FILE"
    exit 1
fi

exec > >(tee -a "$LOG_FILE")
exec 2>&1

echo -e "${YELLOW}正在检查可升级软件包...${NC}"
UPGRADABLE_COUNT=$(apt list --upgradable 2>/dev/null | grep -v "^Listing" | wc -l)

if [ $UPGRADABLE_COUNT -eq 0 ]; then
    echo -e "${GREEN}没有需要升级的软件包${NC}"
    echo "正在删除脚本和日志..."
    rm -f "${ROOT_DIR}/${SCRIPT_NAME}" "$LOG_FILE"
    exit 0
fi

echo -e "${YELLOW}检测到 ${UPGRADABLE_COUNT} 个可升级软件包${NC}"
read -p "是否要执行升级？[Y/n] " -n 1 -r
echo
[[ $REPLY =~ ^[Nn]$ ]] && exit 0

# 升级操作函数
perform_upgrade() {
    local counter_file=$(mktemp)
    echo 0 > "$counter_file"
    
    # 通过进度处理器显示实时进度
    apt-get "$@" -y 2>&1 | stdbuf -oL progress_handler | stdbuf -oL tee -a "$LOG_FILE"
    
    local exit_code=${PIPESTATUS[0]}
    local upgraded=$(<"$counter_file")
    rm "$counter_file"

    if [ $exit_code -ne 0 ]; then
        FAIL_COUNT=$((FAIL_COUNT + 1))
    else
        SUCCESS_COUNT=$((SUCCESS_COUNT + upgraded))
    fi
}

echo -e "${YELLOW}\n正在更新软件包列表...${NC}"
apt-get update |& stdbuf -oL sed 's/^/    /' | stdbuf -oL tee -a "$LOG_FILE"
[ ${PIPESTATUS[0]} -ne 0 ] && FAIL_COUNT=$((FAIL_COUNT + 1))

echo -e "${YELLOW}\n正在执行标准升级...${NC}"
perform_upgrade upgrade

echo -e "${YELLOW}\n正在执行深度升级...${NC}"
perform_upgrade dist-upgrade

echo -e "${YELLOW}\n清理不需要的软件包...${NC}"
apt-get autoremove -y |& stdbuf -oL sed 's/^/    /'
apt-get autoclean

echo -e "\n${GREEN}升级完成！${NC}"
echo -e "成功升级软件包: ${SUCCESS_COUNT} 个"
echo -e "遇到错误次数:    ${FAIL_COUNT} 次"
echo -e "日志文件路径:    ${LOG_FILE}"

if [ -f "/var/run/reboot-required" ]; then
    echo -e "${RED}\n系统需要重启！执行命令: sudo reboot${NC}"
fi

read -p "是否要删除本脚本和日志文件？[y/N] " -n 1 -r
echo
[[ $REPLY =~ ^[Yy]$ ]] && rm -f "${ROOT_DIR}/${SCRIPT_NAME}" "$LOG_FILE"
