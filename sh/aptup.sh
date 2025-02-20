#!/bin/bash

# ================== 配置部分 ==================
ROOT_DIR="/root"
SCRIPT_NAME="aptup.sh"
TIMESTAMP=$(date +%Y%m%d%H%M%S)
LOG_FILE="${ROOT_DIR}/upgrade_${TIMESTAMP}.log"
LOCK_TIMEOUT=300  # 锁等待超时时间（秒）
RETRY_COUNT=3     # 命令重试次数

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # 无颜色

# ================== 初始化部分 ==================
SUCCESS_COUNT=0
FAIL_COUNT=0
declare -A PACKAGE_VERSIONS  # 记录软件包版本变化

# ================== 函数定义 ==================

# 进度处理器（带颜色和图标）
progress_handler() {
    local count=0
    while IFS= read -r line; do
        # 终端显示处理
        if [[ "$line" =~ ^(Unpacking|Preparing to unpack)\ ([^[:space:]]+) ]]; then
            echo -e "${CYAN}▷ 解包: ${BASH_REMATCH[2]}${NC}" >&2
        elif [[ "$line" =~ ^Setting\ up\ ([^[:space:]]+) ]]; then
            echo -e "${GREEN}✓ 安装: ${BASH_REMATCH[1]}${NC}" >&2
            ((count++))
        elif [[ "$line" =~ ^(E:|错误：|Err:) ]]; then
            echo -e "${RED}✖ 错误: ${line#*: }${NC}" >&2
        elif [[ "$line" =~ ^(Get:|Ign:|Hit:) ]]; then
            echo -e "${YELLOW}ℹ ${line}${NC}" >&2
        fi
        echo "$line"  # 原始输出仍写入日志
    done
    echo $count  # 返回成功计数
}

# 带重试的命令执行
retry_command() {
    local cmd=$*
    local attempt=1
    while [ $attempt -le $RETRY_COUNT ]; do
        echo -e "${YELLOW}尝试执行 ($attempt/$RETRY_COUNT): $cmd${NC}"
        if eval "$cmd"; then
            return 0
        fi
        sleep $((attempt * 5))
        ((attempt++))
    done
    return 1
}

# 检查并等待锁释放
check_dpkg_lock() {
    local start_time=$(date +%s)
    while [ $(($(date +%s) - start_time)) -lt $LOCK_TIMEOUT ]; do
        if lsof /var/lib/dpkg/lock-frontend || lsof /var/lib/dpkg/lock; then
            echo -e "${YELLOW}检测到锁被占用，等待释放...$(date +%H:%M:%S)${NC}"
            sleep 5
        else
            return 0
        fi
    done
    echo -e "${RED}错误：等待锁超时${NC}"
    exit 1
}

# 版本比较函数
record_versions() {
    echo -e "${YELLOW}记录当前软件包版本...${NC}"
    dpkg -l | awk '/^ii/ {print \$2"="\$3}' > /tmp/versions_before
}

compare_versions() {
    echo -e "\n${CYAN}版本变更报告：${NC}"
    dpkg -l | awk '/^ii/ {print \$2"="\$3}' > /tmp/versions_after
    diff --color=always /tmp/versions_{before,after} | grep '>' | sed 's/> //'
    rm /tmp/versions_{before,after}
}

# ================== 主流程 ==================
[ "$EUID" -ne 0 ] && { echo -e "${RED}错误：需要root权限执行${NC}"; exit 1; }

# 日志记录设置
exec > >(tee -a "$LOG_FILE")
exec 2>&1

# 检查锁状态
check_dpkg_lock

# 记录初始版本
record_versions

# 检查可升级包
echo -e "${YELLOW}正在检查可升级软件包...${NC}"
UPGRADABLE_COUNT=$(apt list --upgradable 2>/dev/null | grep -c -v "^Listing")

if [ $UPGRADABLE_COUNT -eq 0 ]; then
    echo -e "${GREEN}没有需要升级的软件包${NC}"
    exit 0
fi

# 用户确认
echo -e "${YELLOW}检测到 ${UPGRADABLE_COUNT} 个可升级软件包${NC}"
read -p "是否要执行升级？[Y/n] " -n 1 -r
echo
[[ $REPLY =~ ^[Nn]$ ]] && exit 0

# 执行升级流程
echo -e "${YELLOW}\n[阶段1] 更新软件包列表...${NC}"
retry_command "apt-get update" || FAIL_COUNT=$((FAIL_COUNT + 1))

perform_upgrade() {
    echo -e "${YELLOW}\n[阶段2] 执行 \$1 升级...${NC}"
    local output=$(mktemp)
    
    # 执行命令并捕获输出
    { apt-get "\$1" -y 2>&1 | progress_handler > "$output"; } 2>&1
    
    # 解析结果
    local exit_code=${PIPESTATUS[0]}
    local upgraded=$(grep -c '^✓ 安装:' "$output")
    
    # 显示原始输出
    cat "$output" | tee -a "$LOG_FILE"
    rm "$output"
    
    if [ $exit_code -eq 0 ]; then
        SUCCESS_COUNT=$((SUCCESS_COUNT + upgraded))
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

perform_upgrade upgrade
perform_upgrade dist-upgrade

# 清理阶段
echo -e "${YELLOW}\n[阶段3] 执行清理...${NC}"
{
    retry_command "apt-get autoremove -y" && \
    retry_command "apt-get autoclean"
} || FAIL_COUNT=$((FAIL_COUNT + 1))

# 显示报告
compare_versions
echo -e "\n${GREEN}升级完成！${NC}"
echo -e "成功升级包数: ${SUCCESS_COUNT} 个"
echo -e "遇到错误次数:    ${FAIL_COUNT} 次"
echo -e "完整日志路径:    ${LOG_FILE}"

# 重启提示
if [ -f "/var/run/reboot-required" ]; then
    echo -e "${RED}\n[!] 系统需要重启！执行命令: sudo reboot${NC}"
fi

# 清理脚本（可选）
if [ -z "\$1" ]; then
    read -p "是否要删除本脚本？[y/N] " -n 1 -r
    [[ $REPLY =~ ^[Yy]$ ]] && rm -- "\$0"
fi
