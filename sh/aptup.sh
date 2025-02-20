#!/bin/bash

# 启用严格错误检查
set -eo pipefail

# 动态时间戳函数
get_timestamp() {
    date +%Y-%m-%d_%H:%M:%S
}

# 定义日志文件（带绝对路径）
LOG_FILE="/var/log/upgrade_log_$(get_timestamp).log"

# 脚本路径跟踪
SCRIPT_PATH=$(realpath "\$0")

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 错误捕获回调
trap 'echo -e "${RED}错误发生在第$LINENO行 [$(get_timestamp)]${NC}" >> "$LOG_FILE"; exit 1' ERR

# 检查执行方式
if [[ "\$0" == *bash* || "\$0" == *sh* ]]; then
    echo -e "${RED}错误：请直接执行脚本（例如 ./aptup.sh），不要使用 source 或 . 命令！${NC}"
    exit 1
fi

# 检查root权限
echo -e "\n${BLUE}[$(get_timestamp)] 检查权限...${NC}"
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}错误：请以root用户运行此脚本！${NC}"
    exit 1
fi

# 初始化日志
{
    echo -e "[$(get_timestamp)] 脚本开始执行"
    echo -e "[$(get_timestamp)] 日志文件: $LOG_FILE"
    echo -e "[$(get_timestamp)] 脚本路径: $SCRIPT_PATH"
    echo -e "[$(get_timestamp)] 系统信息: $(lsb_release -ds) | 内核: $(uname -r)"
} >> "$LOG_FILE"

# 更新包列表（带重试机制）
retry_counter=0
max_retries=3
while [ $retry_counter -lt $max_retries ]; do
    echo -e "\n${BLUE}[$(get_timestamp)] 正在更新包列表（尝试 $((retry_counter+1))/$max_retries）...${NC}"
    if apt-get update >> "$LOG_FILE" 2>&1; then
        break
    fi
    ((retry_counter++))
    sleep $((retry_counter*5))
done

if [ $retry_counter -eq $max_retries ]; then
    echo -e "\n${RED}错误：更新包列表失败，请检查日志: $LOG_FILE${NC}" | tee -a "$LOG_FILE"
    exit 1
fi

# 获取升级信息（修正转义符问题）
BEFORE_UPGRADE=$(apt list --upgradable 2>/dev/null | grep -c upgradable)
UPGRADE_INFO=$(apt-get -s dist-upgrade | awk '/^Inst/ {print \$2}')  # 移除非法的转义符

# 无可用更新处理
if [ -z "$UPGRADE_INFO" ] || [ "$BEFORE_UPGRADE" -eq 0 ]; then
    echo -e "\n${BLUE}[$(get_timestamp)] 没有可用的更新。${NC}"
    # 清理旧内核
    echo -e "\n${BLUE}[$(get_timestamp)] 自动清理旧内核...${NC}"
    apt-get autoremove --purge -y >> "$LOG_FILE" 2>&1
    cleanup_result=$?
    
    # 删除处理
    read -p "[$(get_timestamp)] 是否删除脚本和日志？(Y/n) " DELETE
    if [[ "$DELETE" =~ ^[Yy]$ ]]; then
        echo -e "\n${BLUE}[$(get_timestamp)] 删除脚本和日志..."
        rm -f "$SCRIPT_PATH" && echo -e "${GREEN}脚本已删除。${NC}"
        rm -f "$LOG_FILE" && echo -e "${GREEN}日志已删除。${NC}"
    fi
    exit 0
fi

# 显示更新摘要
echo -e "\n${GREEN}[$(get_timestamp)] 检测到以下更新：${NC}"
apt list --upgradable 2>/dev/null | tail -n +2 | awk -F/ '{print \$1}'
echo -e "\n${BLUE}共检测到 $BEFORE_UPGRADE 个可用更新${NC}"

# 确认升级操作
read -p "[$(get_timestamp)] 确认升级？(Y/n) " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo -e "\n${BLUE}[$(get_timestamp)] 用户取消操作。${NC}"
    exit 0
fi

# 执行升级
echo -e "\n${BLUE}[$(get_timestamp)] 正在升级系统...${NC}" | tee -a "$LOG_FILE"
if ! apt-get dist-upgrade -y >> "$LOG_FILE" 2>&1; then
    echo -e "\n${RED}错误：升级失败，尝试修复依赖...${NC}" | tee -a "$LOG_FILE"
    apt-get -f install -y >> "$LOG_FILE" 2>&1 || {
        echo -e "${RED}无法自动修复，请手动检查日志: $LOG_FILE${NC}"
        exit 1
    }
fi

# 清理旧内核
echo -e "\n${BLUE}[$(get_timestamp)] 自动清理旧内核...${NC}"
apt-get autoremove --purge -y >> "$LOG_FILE" 2>&1
cleanup_result=$?

# 统计升级结果
AFTER_UPGRADE=$(apt list --upgradable 2>/dev/null | grep -c upgradable)
SUCCESS=$((BEFORE_UPGRADE - AFTER_UPGRADE))
FAILED=$(grep -ciE 'E: |错误|fail|无法' "$LOG_FILE")

# 生成报告
{
    echo -e "\n===== 升级报告 ====="
    echo "成功升级包数: $SUCCESS"
    echo "失败操作数: $FAILED"
    echo "清理旧内核结果: $([ $cleanup_result -eq 0 ] && echo "成功" || echo "失败")"
    echo "磁盘空间变化: $(df -h / | awk 'NR==2 {print "可用:" \$4 " 使用率:" \$5}')"
    echo "系统负载: $(uptime | awk -F'load average: ' '{print \$2}')"
} | tee -a "$LOG_FILE"

# 服务重启检查
if command -v needrestart &> /dev/null; then
    echo -e "\n${BLUE}[$(get_timestamp)] 检查需要重启的服务...${NC}"
    RESTART_SERVICES=$(needrestart -b 2>/dev/null | awk '/服务需要重启/ {flag=1; next} /^$/ {flag=0} flag')
    if [ -n "$RESTART_SERVICES" ]; then
        echo -e "${RED}以下服务需要手动重启：${NC}"
        echo "$RESTART_SERVICES"
    fi
fi

# 删除处理
read -p "[$(get_timestamp)] 是否删除脚本和日志？(Y/n) " DELETE
if [[ "$DELETE" =~ ^[Yy]$ ]]; then
    echo -e "\n${BLUE}[$(get_timestamp)] 删除脚本和日志..."
    rm -f "$SCRIPT_PATH" && echo -e "${GREEN}脚本已删除。${NC}"
    rm -f "$LOG_FILE" && echo -e "${GREEN}日志已删除。${NC}"
else
    echo -e "\n${BLUE}[$(get_timestamp)] 脚本保留在: $SCRIPT_PATH"
    echo -e "完整日志路径: $LOG_FILE${NC}"
fi

# 最终系统状态
echo -e "\n${GREEN}[$(get_timestamp)] 升级完成！建议执行：${NC}"
echo -e "1. 检查服务状态: systemctl list-units --type=service --state=failed"
echo -e "2. 查看最近更新: grep ' upgraded' $LOG_FILE"
echo -e "3. 系统重启建议: [ $(uptime -p | grep -q day && echo "建议安排重启") ]"

exit 0
