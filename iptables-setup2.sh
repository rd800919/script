#!/bin/bash

# 检测操作系统并设置相应的防火墙规则
function detect_os_and_configure {
    if [[ -f /etc/debian_version ]]; then
        OS="Debian"
        PKG_MANAGER="apt-get"
    elif [[ -f /etc/redhat-release ]]; then
        OS="RedHat"
        PKG_MANAGER="yum"
    else
        echo "不支持的操作系统"
        exit 1
    fi

    echo "检测到的操作系统: $OS"
    echo "更新系统中..."
    $PKG_MANAGER update -y
    setup_firewall
}

# 设置基本的防火墙配置
function setup_firewall {
    echo "配置基本的防火墙规则和IP转发..."
    echo "net.ipv4.ip_forward = 1" | tee -a /etc/sysctl.conf
    sysctl -p

    if [[ $OS == "Debian" ]]; then
        if iptables -V | grep -q "nf_tables"; then
            echo "系统使用 nf_tables 后端的 iptables"
            # Debian 使用 nftables 的处理方式
        else
            echo "系统使用传统 iptables"
            # Debian 使用传统 iptables 的处理方式
        fi
    elif [[ $OS == "RedHat" ]]; then
        echo "系统使用传统 iptables"
        # RedHat 使用传统 iptables 的处理方式
    fi
}

# 配置端口转发
function configure_nat {
    read -p "请输入需要中转的外部 IP: " target_ip
    read -p "请输入TCP/UDP起始端口: " start_port
    read -p "请输入TCP/UDP结束端口: " end_port

    echo "获取内网 IP 地址..."
    internal_ip=$(ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    echo "检测到的内网 IP 地址: $internal_ip"

    echo "设置 iptables 转发规则..."
    iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
    iptables -t nat -A PREROUTING -p tcp --dport $start_port:$end_port -j DNAT --to-destination $target_ip:$start_port-$end_port
    iptables -t nat -A PREROUTING -p udp --dport $start_port:$end_port -j DNAT --to-destination $target_ip:$start_port-$end_port
    echo "转发设置已完成!"
}

# 清除转发规则
function clear_nat {
    echo "清除所有 NAT 转发规则..."
    iptables -t nat -F
    echo "所有转发规则已清除!"
}

# 主菜单
function display_menu {
    clear
    echo "脚本由 BYY 设计"
    echo "WeChat: x7077796"
    echo "============================"
    echo "选择要执行的操作："
    echo "1. 检测系统并安装基本组件"
    echo "2. 设置端口转发"
    echo "3. 清除端口转发"
    echo "4. 退出"
    echo "============================"
}

while true; do
    display_menu
    read -p "请输入选项 (1, 2, 3 或 4): " choice
    case $choice in
        1)
            detect_os_and_configure
            read -p "按任意键继续..." key
            ;;
        2)
            configure_nat
            read -p "按任意键继续..." key
            ;;
        3)
            clear_nat
            read -p "按任意键继续..." key
            ;;
        4)
            echo "退出脚本..."
            exit 0
            ;;
        *)
            echo "无效的选项。请输入 1, 2, 3 或 4。"
            read -p "按任意键继续..." key
            ;;
    esac
done
