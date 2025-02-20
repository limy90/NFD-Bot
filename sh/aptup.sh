#!/bin/bash

# 定义带时间戳的日志文件
TIMESTAMP=$(date +%Y%m%d%H%M%S)
LOG_FILE="/var/log/upgrade_${TIMESTAMP}.log"
REPORT_FILE="/var/log/upgrade_report_${TIMESTAMP}.txt"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # 无颜色

# 检查root权限
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}错误：本脚本需要root权限执行${NC}" | tee -a "$LOG_FILE"
    exit 1
fi

# 函数：错误处理
handle_error() {
    echo -e "${RED}错误发生在第 \$1 行，退出码：\$2${NC}" | tee -a "$LOG_FILE"
    echo -e "${YELLOW}尝试使用 dist-upgrade 修复...${NC}" | tee -a "$LOG_FILE"
    apt-get dist-upgrade -y >> "$LOG_FILE" 2>&1
    if [ $? -ne 0 ]; then
        echo -e "${RED}修复失败，请检查日志文件：$LOG_FILE${NC}" | tee -a "$LOG_FILE"
        exit 1
    fi
}

# 记录所有输出到日志文件
exec > >(tee -a "$LOG_FILE")
exec 2>&1

# 创建系统备份（可选）
echo -e "${YELLOW}创建重要配置文件备份...${NC}"
mkdir -p /var/backup/upgrade_$TIMESTAMP
cp -r /etc/apt/sources.list* /var/backup/upgrade_$TIMESTAMP/
dpkg --get-selections > /var/backup/upgrade_$TIMESTAMP/pkg_selections.list

# 获取升级前包列表
echo -e "${YELLOW}获取当前软件包状态...${NC}"
apt list --upgradable > /tmp/before_upgrade.list 2>/dev/null

# 执行系统更新
echo -e "${YELLOW}正在更新软件包列表...${NC}"
apt-get update
if [ $? -ne 0 ]; then
    handle_error "$LINENO" "$?"
fi

# 执行升级（带错误处理）
echo -e "${YELLOW}正在升级软件包...${NC}"
trap 'handle_error $LINENO $?' ERR
apt-get upgrade -y
trap - ERR

# 执行 dist-upgrade
echo -e "${YELLOW}执行深度升级...${NC}"
apt-get dist-upgrade -y

# 生成升级报告
echo -e "${YELLOW}生成升级报告...${NC}"
{
    echo "系统升级报告 - $(date)"
    echo "--------------------------------"
    echo "升级的软件包列表："
    diff /tmp/before_upgrade.list <(apt list --upgradable 2>/dev/null) | grep '>' | cut -d' ' -f2
    echo -e "\n需要重启的服务："
    checkrestart -v 2>/dev/null || needrestart -b 2>/dev/null || echo "无法检测，请手动运行 checkrestart"
    echo -e "\n磁盘空间变化："
    df -h | grep -v tmpfs
} > "$REPORT_FILE"

# 检查需要重启的服务
echo -e "${YELLOW}检查系统状态...${NC}"
NEED_REBOOT=0
if [ -f "/var/run/reboot-required" ]; then
    echo -e "${RED}系统需要重启！${NC}" | tee -a "$REPORT_FILE"
    NEED_REBOOT=1
fi

# 清理旧包
echo -e "${YELLOW}清理不需要的软件包...${NC}"
apt-get autoremove -y
apt-get autoclean

# 完成提示
echo -e "${GREEN}升级完成！${NC}"
echo -e "日志文件：$LOG_FILE"
echo -e "详细报告：$REPORT_FILE"

# 用户交互
read -p "是否要删除本脚本和日志文件？[y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "删除脚本和日志..."
    rm -f "\$0" "$LOG_FILE" "$REPORT_FILE"
fi

# 重启提示
if [ $NEED_REBOOT -eq 1 ]; then
    echo -e "${RED}建议立即重启系统！执行：sudo reboot${NC}"
fi
