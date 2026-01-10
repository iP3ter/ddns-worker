#!/bin/bash

# =================================================
# Cloudflare Worker DDNS 一键安装管理脚本
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

# 检查是否为 Root 用户
[[ $EUID -ne 0 ]] && echo -e "${RED}错误：${PLAIN} 必须使用 root 用户运行此脚本！\n" && exit 1

# 检查系统依赖
check_dependencies() {
    if ! command -v curl &> /dev/null; then
        echo -e "${YELLOW}正在安装 curl...${PLAIN}"
        if [ -x "$(command -v apt-get)" ]; then
            apt-get update && apt-get install -y curl cron
        elif [ -x "$(command -v yum)" ]; then
            yum install -y curl cronie
        elif [ -x "$(command -v apk)" ]; then
            apk add curl
        else
            echo -e "${RED}无法自动安装 curl，请手动安装！${PLAIN}"
            exit 1
        fi
    fi
}

# 获取用户输入
get_input() {
    echo -e "\n${GREEN}请配置 DDNS 参数：${PLAIN}"
    
    read -p "请输入 Worker 主控地址 (例如 https://cf-ddns-worker.example.workers.dev): " input_url
    [[ -z "$input_url" ]] && echo -e "${RED}地址不能为空${PLAIN}" && exit 1
    
    read -p "请输入通信密钥 (API_SECRET): " input_secret
    [[ -z "$input_secret" ]] && echo -e "${RED}密钥不能为空${PLAIN}" && exit 1
    
    read -p "请输入主域名 (例如 example.com): " input_zone
    [[ -z "$input_zone" ]] && echo -e "${RED}主域名不能为空${PLAIN}" && exit 1
    
    read -p "请输入子域名前缀 (例如 home, 根域名填 @): " input_prefix
    [[ -z "$input_prefix" ]] && input_prefix="@"
    
    read -p "请输入节点名称 (用于通知，默认: Server): " input_node
    [[ -z "$input_node" ]] && input_node="Server"
    
    echo -e "\n请选择记录类型:"
    echo "1) IPv4 (A 记录)"
    echo "2) IPv6 (AAAA 记录)"
    read -p "请选择 [1-2] (默认 1): " type_choice
    case $type_choice in
        2) input_type="AAAA" ;;
        *) input_type="A" ;;
    esac
    
    read -p "请输入更新频率 (分钟，默认 5): " input_freq
    [[ -z "$input_freq" ]] && input_freq="5"
}

# 写入核心脚本
write_core_script() {
    cat > "$INSTALL_PATH" << 'EOF'
#!/usr/bin/env bash
set -o errexit && set -o nounset && set -o pipefail

# 加载配置
CONF_FILE="/etc/cf-ddns/config.env"
if [ -f "$CONF_FILE" ]; then
    source "$CONF_FILE"
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
if [ "$RECORD_TYPE" = "A" ]; then
    WAN_IP=$(curl -fs -4 http://ipv4.icanhazip.com || curl -fs -4 http://api.ipify.org)
elif [ "$RECORD_TYPE" = "AAAA" ]; then
    WAN_IP=$(curl -fs -6 http://ipv6.icanhazip.com || curl -fs -6 http://api6.ipify.org)
else
    log "Error: Invalid record type: $RECORD_TYPE"
    exit 1
fi

if [[ -z "$WAN_IP" ]]; then
    log "Error: Failed to get valid IP address."
    exit 1
fi

# IP数据缓存
LAST_IP_FILE="/tmp/cf-ddns-lastip-${SUBDOMAIN_PREFIX}.txt"

if [ -f "$LAST_IP_FILE" ]; then
    LAST_IP=$(cat "$LAST_IP_FILE")
    if [ "$WAN_IP" = "$LAST_IP" ]; then
        # IP未变动，不记录日志以免刷屏，除非调试
        exit 0
    fi
fi

log "IP changed or first run. Updating ${SUBDOMAIN_PREFIX}.${CF_ZONE_NAME} to ${WAN_IP}..."

# 发送请求
RESPONSE=$(curl -fsS -X POST "$API_BASE_URL" \
    -H "Authorization: Bearer $API_SECRET" \
    -H "Content-Type: application/json" \
    -d "{\"prefix\":\"$SUBDOMAIN_PREFIX\",\"ip\":\"$WAN_IP\",\"zone_name\":\"$CF_ZONE_NAME\",\"type\":\"$RECORD_TYPE\",\"node_name\":\"$NODE_NAME\"}" 2>&1)

if echo "$RESPONSE" | grep -q '"success":true'; then
    log "Update successful! IP: $WAN_IP"
    echo "$WAN_IP" > "$LAST_IP_FILE"
else
    log "Update failed! Response: $RESPONSE"
    # 这里不退出，防止cron报错
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
    crontab -l 2>/dev/null | grep -v "$INSTALL_PATH" | crontab -
    (crontab -l 2>/dev/null; echo "*/$input_freq * * * * $INSTALL_PATH >/dev/null 2>&1") | crontab -
    
    # 首次运行
    echo -e "${GREEN}正在进行首次运行测试...${PLAIN}"
    $INSTALL_PATH
    
    echo -e "${GREEN}安装成功！${PLAIN}"
    echo -e "配置文件: $CONFIG_FILE"
    echo -e "日志文件: $LOG_FILE"
    echo -e "已添加 Crontab 定时任务，每 $input_freq 分钟执行一次。"
}

# 卸载函数
uninstall_ddns() {
    read -p "确定要卸载吗? [y/N] " confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && echo "已取消" && return
    
    # 删除定时任务
    crontab -l 2>/dev/null | grep -v "$INSTALL_PATH" | crontab -
    
    rm -f "$INSTALL_PATH"
    rm -rf "/etc/cf-ddns"
    rm -f "$LOG_FILE"
    rm -f "/tmp/cf-ddns-lastip-*"
    
    echo -e "${GREEN}卸载完成！${PLAIN}"
}

# 查看日志
view_log() {
    if [ -f "$LOG_FILE" ]; then
        tail -n 20 "$LOG_FILE"
    else
        echo -e "${YELLOW}日志文件不存在（可能是尚未运行或没有IP变动）。${PLAIN}"
    fi
}

# 主菜单
menu() {
    clear
    echo -e "#############################################"
    echo -e "#    Cloudflare Worker DDNS 一键管理脚本    #"
    echo -e "#############################################"
    echo -e ""
    echo -e "${GREEN}1.${PLAIN} 安装 / 重装 DDNS"
    echo -e "${GREEN}2.${PLAIN} 卸载 DDNS"
    echo -e "${GREEN}3.${PLAIN} 手动运行一次 (测试)"
    echo -e "${GREEN}4.${PLAIN} 查看运行日志"
    echo -e "${GREEN}5.${PLAIN} 修改配置文件"
    echo -e "${GREEN}0.${PLAIN} 退出"
    echo -e ""
    read -p "请输入数字 [0-5]: " num
    
    case "$num" in
        1) install_ddns ;;
        2) uninstall_ddns ;;
        3) 
            if [ -f "$INSTALL_PATH" ]; then
                echo "正在运行..."
                $INSTALL_PATH
                echo "运行完成，请查看日志。"
                view_log
            else
                echo -e "${RED}尚未安装！${PLAIN}"
            fi
            ;;
        4) view_log ;;
        5) 
            if [ -f "$CONFIG_FILE" ]; then
                ${EDITOR:-vi} "$CONFIG_FILE"
                echo -e "${GREEN}修改完成，下次定时任务将生效。${PLAIN}"
            else
                echo -e "${RED}尚未安装！${PLAIN}"
            fi
            ;;
        0) exit 0 ;;
        *) echo -e "${RED}请输入正确的数字${PLAIN}" ;;
    esac
}

menu
