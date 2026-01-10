#!/bin/sh

# =================================================
# Cloudflare Worker DDNS 一键安装管理脚本
# 兼容 Alpine / Debian / Ubuntu / CentOS
# =================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'

# 路径定义
INSTALL_PATH="/usr/local/bin/cf-ddns"
CONFIG_FILE="/etc/cf-ddns/config.env"
LOG_FILE="/var/log/cf-ddns.log"
SCRIPT_NAME="cf-ddns"

# 打印带颜色的信息
print_msg() {
    printf "${1}${2}${PLAIN}\n"
}

# 检查是否为 Root 用户
if [ "$(id -u)" -ne 0 ]; then
    print_msg "$RED" "错误：必须使用 root 用户运行此脚本！"
    exit 1
fi

# 检测系统类型
detect_os() {
    if [ -f /etc/alpine-release ]; then
        OS="alpine"
        PKG_MGR="apk"
    elif [ -f /etc/debian_version ]; then
        OS="debian"
        PKG_MGR="apt"
    elif [ -f /etc/redhat-release ]; then
        OS="rhel"
        PKG_MGR="yum"
    else
        OS="unknown"
        PKG_MGR=""
    fi
}

# 检查系统依赖
check_dependencies() {
    local need_install=0
    
    print_msg "$GREEN" "正在检查系统依赖..."
    detect_os
    
    # 检查 curl
    if ! command -v curl >/dev/null 2>&1; then
        print_msg "$YELLOW" "[!] curl 未安装"
        need_install=1
    else
        print_msg "$GREEN" "[✓] curl 已安装"
    fi
    
    # 检查 crontab
    if ! command -v crontab >/dev/null 2>&1; then
        print_msg "$YELLOW" "[!] crontab 未安装"
        need_install=1
    else
        print_msg "$GREEN" "[✓] crontab 已安装"
    fi
    
    # 安装缺失的依赖
    if [ $need_install -eq 1 ]; then
        print_msg "$YELLOW" "正在安装缺失的依赖..."
        
        case "$OS" in
            alpine)
                apk update
                apk add --no-cache curl dcron
                # 启动 crond
                if command -v rc-service >/dev/null 2>&1; then
                    rc-update add dcron default 2>/dev/null || true
                    rc-service dcron start 2>/dev/null || true
                else
                    # 直接启动 crond 进程
                    crond 2>/dev/null || true
                fi
                ;;
            debian)
                apt-get update
                apt-get install -y curl cron
                systemctl enable cron 2>/dev/null || true
                systemctl start cron 2>/dev/null || service cron start 2>/dev/null || true
                ;;
            rhel)
                yum install -y curl cronie
                systemctl enable crond 2>/dev/null || true
                systemctl start crond 2>/dev/null || service crond start 2>/dev/null || true
                ;;
            *)
                print_msg "$RED" "无法识别的系统，请手动安装 curl 和 cron"
                exit 1
                ;;
        esac
    fi
    
    # 最终验证
    print_msg "$GREEN" "验证依赖安装..."
    
    if ! command -v curl >/dev/null 2>&1; then
        print_msg "$RED" "[✗] curl 安装失败"
        exit 1
    fi
    
    if ! command -v crontab >/dev/null 2>&1; then
        print_msg "$RED" "[✗] crontab 安装失败"
        exit 1
    fi
    
    # 确保 cron 服务运行
    check_cron_running
    
    print_msg "$GREEN" "所有依赖检查通过！"
}

# 检查 cron 是否运行
check_cron_running() {
    if pgrep -x "crond" >/dev/null 2>&1 || pgrep -x "cron" >/dev/null 2>&1; then
        print_msg "$GREEN" "[✓] cron 服务运行中"
    else
        print_msg "$YELLOW" "[!] 正在启动 cron 服务..."
        case "$OS" in
            alpine)
                crond 2>/dev/null || rc-service dcron start 2>/dev/null || true
                ;;
            debian)
                systemctl start cron 2>/dev/null || service cron start 2>/dev/null || true
                ;;
            rhel)
                systemctl start crond 2>/dev/null || service crond start 2>/dev/null || true
                ;;
        esac
        
        sleep 1
        if pgrep -x "crond" >/dev/null 2>&1 || pgrep -x "cron" >/dev/null 2>&1; then
            print_msg "$GREEN" "[✓] cron 服务已启动"
        else
            print_msg "$YELLOW" "[!] 请手动检查 cron 服务状态"
        fi
    fi
}

# 读取用户输入（兼容 Alpine）
read_input() {
    printf "%s" "$1"
    read input_value
    echo "$input_value"
}

# 获取用户输入
get_input() {
    printf "\n"
    print_msg "$GREEN" "请配置 DDNS 参数："
    
    printf "请输入 Worker 主控地址 (例如 https://cf-ddns-worker.example.workers.dev): "
    read input_url
    if [ -z "$input_url" ]; then
        print_msg "$RED" "地址不能为空"
        exit 1
    fi
    
    printf "请输入通信密钥 (API_SECRET): "
    read input_secret
    if [ -z "$input_secret" ]; then
        print_msg "$RED" "密钥不能为空"
        exit 1
    fi
    
    printf "请输入主域名 (例如 example.com): "
    read input_zone
    if [ -z "$input_zone" ]; then
        print_msg "$RED" "主域名不能为空"
        exit 1
    fi
    
    printf "请输入子域名前缀 (例如 home, 根域名填 @): "
    read input_prefix
    [ -z "$input_prefix" ] && input_prefix="@"
    
    printf "请输入节点名称 (用于通知，默认: Server): "
    read input_node
    [ -z "$input_node" ] && input_node="Server"
    
    printf "\n请选择记录类型:\n"
    printf "1) IPv4 (A 记录)\n"
    printf "2) IPv6 (AAAA 记录)\n"
    printf "请选择 [1-2] (默认 1): "
    read type_choice
    case $type_choice in
        2) input_type="AAAA" ;;
        *) input_type="A" ;;
    esac
    
    printf "请输入更新频率 (分钟，默认 5): "
    read input_freq
    [ -z "$input_freq" ] && input_freq="5"
}

# 写入核心脚本
write_core_script() {
    cat > "$INSTALL_PATH" << 'EOF'
#!/bin/sh
set -e

# 加载配置
CONF_FILE="/etc/cf-ddns/config.env"
if [ -f "$CONF_FILE" ]; then
    . "$CONF_FILE"
else
    echo "Config file not found!"
    exit 1
fi

LOG_FILE="/var/log/cf-ddns.log"

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# 自动检测IP
WAN_IP=""
if [ "$RECORD_TYPE" = "A" ]; then
    WAN_IP=$(curl -fs -4 http://ipv4.icanhazip.com 2>/dev/null || curl -fs -4 http://api.ipify.org 2>/dev/null || echo "")
elif [ "$RECORD_TYPE" = "AAAA" ]; then
    WAN_IP=$(curl -fs -6 http://ipv6.icanhazip.com 2>/dev/null || curl -fs -6 http://api6.ipify.org 2>/dev/null || echo "")
else
    log "Error: Invalid record type: $RECORD_TYPE"
    exit 1
fi

if [ -z "$WAN_IP" ]; then
    log "Error: Failed to get valid IP address."
    exit 1
fi

# IP数据缓存
LAST_IP_FILE="/tmp/cf-ddns-lastip-${SUBDOMAIN_PREFIX}.txt"

if [ -f "$LAST_IP_FILE" ]; then
    LAST_IP=$(cat "$LAST_IP_FILE")
    if [ "$WAN_IP" = "$LAST_IP" ]; then
        exit 0
    fi
fi

log "IP changed or first run. Updating ${SUBDOMAIN_PREFIX}.${CF_ZONE_NAME} to ${WAN_IP}..."

# 发送请求
RESPONSE=$(curl -fsS -X POST "$API_BASE_URL" \
    -H "Authorization: Bearer $API_SECRET" \
    -H "Content-Type: application/json" \
    -d "{\"prefix\":\"$SUBDOMAIN_PREFIX\",\"ip\":\"$WAN_IP\",\"zone_name\":\"$CF_ZONE_NAME\",\"type\":\"$RECORD_TYPE\",\"node_name\":\"$NODE_NAME\"}" 2>&1) || true

if echo "$RESPONSE" | grep -q '"success":true'; then
    log "Update successful! IP: $WAN_IP"
    echo "$WAN_IP" > "$LAST_IP_FILE"
else
    log "Update failed! Response: $RESPONSE"
fi
EOF
    chmod +x "$INSTALL_PATH"
}

# 安装函数
install_ddns() {
    check_dependencies
    get_input
    
    mkdir -p /etc/cf-ddns
    
    # 写入配置文件
    cat > "$CONFIG_FILE" << EOF
API_BASE_URL="$input_url"
API_SECRET="$input_secret"
SUBDOMAIN_PREFIX="$input_prefix"
CF_ZONE_NAME="$input_zone"
RECORD_TYPE="$input_type"
NODE_NAME="$input_node"
EOF

    # 写入脚本
    write_core_script
    
    # 设置定时任务
    crontab -l 2>/dev/null | grep -v "$INSTALL_PATH" > /tmp/cron_tmp || true
    echo "*/$input_freq * * * * $INSTALL_PATH >/dev/null 2>&1" >> /tmp/cron_tmp
    crontab /tmp/cron_tmp
    rm -f /tmp/cron_tmp
    
    # 首次运行
    print_msg "$GREEN" "正在进行首次运行测试..."
    $INSTALL_PATH || true
    
    print_msg "$GREEN" "安装成功！"
    printf "配置文件: %s\n" "$CONFIG_FILE"
    printf "日志文件: %s\n" "$LOG_FILE"
    printf "已添加 Crontab 定时任务，每 %s 分钟执行一次。\n" "$input_freq"
}

# 卸载函数
uninstall_ddns() {
    printf "确定要卸载吗? [y/N] "
    read confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "已取消"
        return
    fi
    
    # 删除定时任务
    crontab -l 2>/dev/null | grep -v "$INSTALL_PATH" > /tmp/cron_tmp || true
    crontab /tmp/cron_tmp 2>/dev/null || true
    rm -f /tmp/cron_tmp
    
    rm -f "$INSTALL_PATH"
    rm -rf "/etc/cf-ddns"
    rm -f "$LOG_FILE"
    rm -f /tmp/cf-ddns-lastip-*
    
    print_msg "$GREEN" "卸载完成！"
}

# 查看日志
view_log() {
    if [ -f "$LOG_FILE" ]; then
        tail -n 20 "$LOG_FILE"
    else
        print_msg "$YELLOW" "日志文件不存在（可能是尚未运行或没有IP变动）。"
    fi
}

# 主菜单
menu() {
    clear
    printf "#############################################\n"
    printf "#    Cloudflare Worker DDNS 一键管理脚本    #\n"
    printf "#############################################\n"
    printf "\n"
    print_msg "$GREEN" "1. 安装 / 重装 DDNS"
    print_msg "$GREEN" "2. 卸载 DDNS"
    print_msg "$GREEN" "3. 手动运行一次 (测试)"
    print_msg "$GREEN" "4. 查看运行日志"
    print_msg "$GREEN" "5. 修改配置文件"
    print_msg "$GREEN" "0. 退出"
    printf "\n"
    printf "请输入数字 [0-5]: "
    read num
    
    case "$num" in
        1) install_ddns ;;
        2) uninstall_ddns ;;
        3) 
            if [ -f "$INSTALL_PATH" ]; then
                echo "正在运行..."
                $INSTALL_PATH || true
                echo "运行完成，请查看日志。"
                view_log
            else
                print_msg "$RED" "尚未安装！"
            fi
            ;;
        4) view_log ;;
        5) 
            if [ -f "$CONFIG_FILE" ]; then
                ${EDITOR:-vi} "$CONFIG_FILE"
                print_msg "$GREEN" "修改完成，下次定时任务将生效。"
            else
                print_msg "$RED" "尚未安装！"
            fi
            ;;
        0) exit 0 ;;
        *) print_msg "$RED" "请输入正确的数字" ;;
    esac
}

menu
