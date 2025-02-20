#!/bin/bash

# ================== 全局配置 ==================
ROOT_DIR="/root"
SCRIPT_NAME="aptup.sh"
TIMESTAMP=$(date +%Y%m%d%H%M%S)
LOG_FILE="${ROOT_DIR}/upgrade_${TIMESTAMP}.log"
LOCK_TIMEOUT=300       # 锁等待超时时间（秒）
RETRY_COUNT=3          # 命令重试次数
LOCK_FILES=(           # 需要检测的锁文件
    "/var/lib/dpkg/lock-frontend"
    "/var/lib/dpkg/lock"
    "/var/cache/apt/archives/lock"
)

# ================== 颜色定义 ==================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

# ================== 初始化部分 ==================
SUCCESS_COUNT=0
FAIL_COUNT=0
declare -A PACKAGE_VERSIONS

# ================== 函数定义 ==================

# 带颜色和图标的状态显示
status_msg() {
    case \$1 in
        info)    echo -e "${BLUE}ℹ \$2${NC}" ;;
        success) echo -e "${GREEN}✓ \$2${NC}" ;;
        warn)    echo -e "${YELLOW}⚠ \$2${NC}" ;;
        error)   echo -e "${RED}✖ \$2${NC}" ;;
        proc)    echo -e "${CYAN}» \$2${NC}" ;;
    esac | tee -a "$LOG_FILE"
}

# 显示进程树（兼容无pstree环境）
show_process_tree() {
    local pid=\$1
    if command -v pstree >/dev/null 2>&1; then
        echo -e "进程树: $(pstree -s -p $pid 2>/dev/null || echo '无法显示')"
    else
        # 获取父进程信息（处理空值和无效PID）
        local ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | awk '{print \$1}')
        if [ -n "$ppid" ] && [ "$ppid" -ne 0 ] 2>/dev/null; then
            local parent_cmd=$(ps -o cmd= -p "$ppid" 2>/dev/null || echo '未知')
            echo -e "父进程[$ppid]: $parent_cmd"
        else
            echo -e "父进程: 无"
        fi

        # 获取当前进程命令行
        local current_cmd=$(ps -p "$pid" -o cmd= --no-headers 2>/dev/null || echo '无法获取')
        echo -e "命令行: $current_cmd"
        echo -e "提示: 安装 ${YELLOW}psmisc${NC} 包可查看完整进程树 (sudo apt install psmisc)"
    fi
}

# 智能锁检测与处理
check_dpkg_lock() {
    local start_time=$(date +%s)
    
    while :; do
        local locked=0
        # 检测所有相关锁文件
        for lock_file in "${LOCK_FILES[@]}"; do
            # 检测实际占用进程
            if lsof -t "$lock_file" >/dev/null; then
                locked=1
                local pids=($(lsof -t "$lock_file"))
                local pid=${pids[0]}  # 取第一个PID
                if [ -z "$pid" ]; then
                    status_msg warn "检测到锁占用，但无法获取进程ID"
                    continue
                fi
                status_msg warn "检测到锁占用：$lock_file"
                status_msg info "占用进程PID: $pid"
                show_process_tree "$pid"
                # 尝试修复未完成的dpkg配置
                if pgrep -x "dpkg" >/dev/null; then
                    status_msg info "尝试修复未完成的dpkg配置..."
                    sudo dpkg --configure -a
                fi
            elif [ -e "$lock_file" ]; then
                status_msg warn "发现残留锁文件：$lock_file"
                if rm -f "$lock_file" 2>/dev/null; then
                    status_msg success "已安全移除残留锁"
                else
                    status_msg error "无法移除锁文件，请手动处理"
                    exit 1
                fi
            fi
        done

        # 超时处理
        if [ $(($(date +%s) - start_time)) -gt $LOCK_TIMEOUT ]; then
            status_msg error "等待锁超时（${LOCK_TIMEOUT}秒）"
            echo -e "${YELLOW}建议操作：\n1. 运行修复命令：sudo dpkg --configure -a\n2. 终止占用进程：sudo kill -9 $(lsof -t /var/lib/dpkg/lock-frontend)\n3. 删除锁文件：sudo rm ${LOCK_FILES[@]}\n4. 重启系统${NC}" | tee -a "$LOG_FILE"
            exit 1
        fi

        [ $locked -eq 0 ] && break
        
        # 指数退避等待
        local wait_time=$(( (RANDOM % 10) + 5 ))
        status_msg info "等待锁释放（剩余时间：$((LOCK_TIMEOUT - ($(date +%s) - start_time)))秒）"
        sleep $wait_time
    done
}

# 带重试的命令执行
retry_command() {
    local cmd=$*
    local attempt=1
    while [ $attempt -le $RETRY_COUNT ]; do
        status_msg info "尝试执行 ($attempt/$RETRY_COUNT): ${cmd%% *}"
        if eval "$cmd"; then
            return 0
        fi
        sleep $((attempt * 5))
        ((attempt++))
    done
    status_msg error "命令重试次数耗尽：$cmd"
    return 1
}

# 实时进度处理器
progress_handler() {
    local count=0
    while IFS= read -r line; do
        # 终端显示处理
        case "$line" in
            *Unpacking*)
                status_msg proc "解包: $(awk '{print \$2}' <<< "$line")" ;;
            *Setting\ up*)
                status_msg success "安装: $(awk '{print \$3}' <<< "$line")"
                ((count++)) ;;
            *ERROR*|*E:*|*错误*)
                status_msg error "${line#*: }" ;;
            *http*|*Hit*|*Ign*)
                status_msg info "$line" ;;
        esac
        echo "$line"  # 原始日志
    done
    echo $count
}

# 版本记录与比较
record_versions() {
    status_msg info "记录当前软件版本..."
    dpkg -l | awk '/^ii/ {print \$2"="\$3}' > /tmp/versions_before
}

compare_versions() {
    status_msg info "生成版本变更报告..."
    dpkg -l | awk '/^ii/ {print \$2"="\$3}' > /tmp/versions_after
    echo -e "\n${GREEN}=== 版本变更明细 ===${NC}"
    diff --color=always /tmp/versions_{before,after} | grep '>' | sed 's/> //'
    rm /tmp/versions_{before,after}
}

# ================== 主流程 ==================
[ "$EUID" -ne 0 ] && { status_msg error "需要root权限执行"; exit 1; }

# 初始化日志
exec > >(tee -a "$LOG_FILE")
exec 2>&1
status_msg info "启动系统更新 (日志文件: $LOG_FILE)"

# 锁检测
check_dpkg_lock

# 版本快照
record_versions

# 检查可升级包
status_msg info "检查可升级软件包..."
UPGRADABLE=$(apt list --upgradable 2>/dev/null | grep -v "^Listing")
UPGRADABLE_COUNT=$(wc -l <<< "$UPGRADABLE")

if [ $UPGRADABLE_COUNT -eq 0 ]; then
    status_msg success "没有可升级软件包"
    exit 0
fi

# 显示可升级列表
echo -e "\n${CYAN}可升级软件包列表：${NC}"
awk -F/ '{print "  " \$1}' <<< "$UPGRADABLE"
echo -e "${YELLOW}总计: ${UPGRADABLE_COUNT} 个软件包${NC}"

# 用户确认
read -p "是否继续升级？[Y/n] " -n 1 -r
echo
[[ $REPLY =~ ^[Nn]$ ]] && exit 0

# 执行升级流程
{
    # 阶段1：更新索引
    status_msg info "阶段1/3 - 更新软件包列表"
    retry_command "apt-get update" || FAIL_COUNT=$((FAIL_COUNT+1))

    # 阶段2：执行升级
    perform_upgrade() {
        status_msg info "阶段2/3 - 执行 \$1 升级"
        local output=$(mktemp)
        
        # 执行升级命令
        { apt-get "\$1" -y 2>&1 | progress_handler > "$output"; } 2>&1
        
        # 处理结果
        local exit_code=${PIPESTATUS[0]}
        local upgraded=$(grep -c '^✓ 安装:' "$output")
        
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

    # 阶段3：清理
    status_msg info "阶段3/3 - 系统清理"
    retry_command "apt-get autoremove -y" && \
    retry_command "apt-get autoclean" || \
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

# 生成报告
compare_versions
echo -e "\n${GREEN}=== 操作摘要 ==="
echo -e "成功升级包数: ${SUCCESS_COUNT} 个"
echo -e "遇到错误次数:    ${FAIL_COUNT} 次"
echo -e "日志文件位置:    ${LOG_FILE}${NC}"

# 重启提示
if [ -f "/var/run/reboot-required" ]; then
    status_msg warn "系统需要重启！执行命令: sudo reboot"
fi

# 脚本自清理
if [ -z "\$1" ]; then
    read -p "是否删除本脚本？[y/N] " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]] && rm -- "\$0"
fi

exit 0
