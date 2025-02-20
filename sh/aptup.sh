#!/bin/bash

# 获取升级信息（优化版）
get_upgrade_info() {
    local lang_backup="$LANG"
    export LANG=C
    
    local upgrade_list=$(apt list --upgradable 2>/dev/null)
    BEFORE_UPGRADE=$(echo "$upgrade_list" | grep -c upgradable)
    UPGRADE_INFO=$(echo "$upgrade_list" | grep 'upgradable' | cut -d/ -f1)  # 修改点1
    
    export LANG="$lang_backup"
}

# 显示更新摘要
echo -e "\n${GREEN}[$(get_timestamp)] 检测到以下更新：${NC}"
apt list --upgradable 2>/dev/null | tail -n +2 | cut -d/ -f1  # 修改点2

# ...（中间部分保持不变）...

# 生成报告
{
    echo -e "\n===== 升级报告 ====="
    echo "成功升级包数: $SUCCESS"
    echo "失败操作数: $FAILED"
    echo "清理旧内核结果: $([ $cleanup_result -eq 0 ] && echo "成功" || echo "失败")"
    
    # 修改点3：磁盘空间报告
    df_line=$(df -h / | tail -n1 | tr -s ' ')
    available=$(echo "$df_line" | cut -d ' ' -f4)
    used_pct=$(echo "$df_line" | cut -d ' ' -f5)
    echo "磁盘空间变化: 可用:$available 使用率:$used_pct"
    
    # 修改点4：系统负载
    echo "系统负载: $(uptime | sed 's/.*load average: //')"
} | tee -a "$LOG_FILE"

# 服务重启检查（修改点5）
if command -v needrestart &> /dev/null; then
    echo -e "\n${BLUE}[$(get_timestamp)] 检查需要重启的服务...${NC}"
    RESTART_SERVICES=$(needrestart -b 2>/dev/null | sed -n '/服务需要重启/{:a;n;/^$/q;p;ba}')
    # ...后续不变...
fi

# ...（剩余部分保持不变）...

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
