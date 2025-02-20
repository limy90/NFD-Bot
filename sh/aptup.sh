#!/bin/bash

# 定义日志文件和时间戳
LOG_FILE="upgrade_log_$(date +%Y-%m-%d_%H:%M:%S).log"
TimeStamp=$(date +%Y-%m-%d_%H:%M:%S)

# 检查执行方式：禁止通过 source 或 . 执行
if [[ "\$0" == *bash* || "\$0" == *sh* ]]; then
    echo -e "错误：请直接执行脚本（例如 ./script.sh），不要使用 source 或 . 命令！"
    exit 1
fi

# 获取脚本绝对路径
SCRIPT_PATH=$(realpath "\$0")

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

# 检查root权限
echo -e "\n${BLUE}[$TimeStamp] 检查权限...${NC}"
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}错误：请以root用户运行此脚本！${NC}"
    exit 1
fi

# 初始化日志文件
echo -e "[$TimeStamp] 脚本开始执行。" > "$LOG_FILE"
echo -e "[$TimeStamp] 日志文件: $LOG_FILE" >> "$LOG_FILE"

# 更新包列表
echo -e "\n${BLUE}[$TimeStamp] 正在更新包列表...${NC}"
if ! apt-get update >> "$LOG_FILE" 2>&1; then
    echo -e "\n${RED}错误：更新包列表失败，请检查日志: $LOG_FILE${NC}"
    exit 1
fi

# 获取可升级的包名（修复转义问题）
echo -e "\n${BLUE}[$TimeStamp] 检查可升级的包...${NC}"
UPGRADE_INFO=$(apt-get -s upgrade | awk '/^Inst/ {print \$2}')

if [ -z "$UPGRADE_INFO" ]; then
    echo -e "\n${BLUE}[$TimeStamp] 没有可用的更新。${NC}"
    
    # 询问是否删除脚本和日志
    read -p "[$TimeStamp] 是否删除脚本和日志？(Y/n) " DELETE
    if [[ "$DELETE" =~ ^[Yy]$ ]]; then
        echo -e "\n${BLUE}[$TimeStamp] 删除脚本和日志...${NC}"
        if [ -f "$SCRIPT_PATH" ]; then
            rm -f "$SCRIPT_PATH" && echo -e "${GREEN}脚本已删除。${NC}"
        else
            echo -e "${RED}警告：脚本路径不存在，请直接执行脚本（例如 ./script.sh）！${NC}"
        fi
        rm -f "$LOG_FILE" && echo -e "${GREEN}日志已删除。${NC}"
    else
        echo -e "\n${BLUE}[$TimeStamp] 保留脚本和日志。${NC}"
    fi
    exit 0
else
    echo -e "\n${GREEN}[$TimeStamp] 检测到可升级的包，开始升级...${NC}"
fi

# 确认升级操作
read -p "[$TimeStamp] 确认升级？(Y/n) " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo -e "\n${BLUE}[$TimeStamp] 用户取消操作。${NC}"
    exit 0
fi

# 执行升级
echo -e "\n${BLUE}[$TimeStamp] 正在升级系统...${NC}" | tee -a "$LOG_FILE"
if ! apt-get upgrade -y >> "$LOG_FILE" 2>&1; then
    echo -e "\n${RED}错误：升级失败，尝试修复依赖...${NC}" | tee -a "$LOG_FILE"
    apt-get -f install -y >> "$LOG_FILE" 2>&1 || {
        echo -e "${RED}无法自动修复，请手动检查日志: $LOG_FILE${NC}"
        exit 1
    }
fi

# 输出结果统计
SUCCESS=$(grep -c '^Inst' "$LOG_FILE")
FAILED=$(grep -c 'E: \|错误' "$LOG_FILE")
echo -e "\n${GREEN}升级成功: $SUCCESS 个包${NC}"
echo -e "${RED}失败: $FAILED 个包${NC}"

# 询问是否删除脚本和日志
read -p "[$TimeStamp] 是否删除脚本和日志？(Y/n) " DELETE
if [[ "$DELETE" =~ ^[Yy]$ ]]; then
    echo -e "\n${BLUE}[$TimeStamp] 删除脚本和日志...${NC}"
    if [ -f "$SCRIPT_PATH" ]; then
        rm -f "$SCRIPT_PATH" && echo -e "${GREEN}脚本已删除。${NC}"
    else
        echo -e "${RED}警告：脚本路径不存在，请直接执行脚本（例如 ./script.sh）！${NC}"
    fi
    rm -f "$LOG_FILE" && echo -e "${GREEN}日志已删除。${NC}"
else
    echo -e "\n${BLUE}[$TimeStamp] 保留脚本和日志。${NC}"
fi

exit 0
