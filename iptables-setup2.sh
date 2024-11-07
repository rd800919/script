#!/bin/bash

# Script for setting up IP forwarding and iptables configuration.

function display_menu {
    clear
    echo "脚本由 BYY 设计"
    echo "WeChat: x7077796"
    echo "============================"
    echo "选择要执行的操作："
    echo "1. 执行事前准备和安装"
    echo "2. 设置转发"
    echo "3. 退出"
    echo "============================"
}

function detect_os {
    if [[ -f /etc/debian_version ]]; then
        OS="Debian"
        PKG_MANAGER="apt-get"
        FIREWALL_CTRL="systemctl"
    elif [[ -f /etc/redhat-release ]]; then
        OS="RedHat"
        PKG_MANAGER="yum"
        FIREWALL_CTRL="systemctl"
    else
        echo "不支持的操作系统"
        exit 1
    fi
}

function setup_iptables {
    detect_os
    echo "更新系统..."
    $PKG_MANAGER update -y
    $FIREWALL_CTRL stop firewalld
    $FIREWALL_CTRL disable firewalld
    $PKG_MANAGER install iptables-services -y
    $FIREWALL_CTRL enable iptables
    $FIREWALL_CTRL start iptables

    echo "设置 IP 转发..."
    echo "#. Controls IP packet forwarding" >> /etc/sysctl.conf
    echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
    sysctl -p

    echo "事前准备和安装已完成!"
}

function configure_nat {
    read -p "请输入需要中转的外部 IP: " target_ip
    read -p "请输入TCP/UDP端口范围 (例如 10000-10002): " port_range

    echo "获取内网 IP 地址..."
    internal_ip=$(ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    echo "检测到的内网 IP 地址: $internal_ip"

    echo "设置 iptables 转发规则..."
    iptables -t nat -A POSTROUTING -d $target_ip -p tcp -m tcp --dport $port_range -j SNAT --to-source $internal_ip
    iptables -t nat -A POSTROUTING -d $target_ip -p udp -m udp --dport $port_range -j SNAT --to-source $internal_ip
    iptables -t nat -A PREROUTING -p tcp -m tcp --dport $port_range -j DNAT --to-destination $target_ip:$port_range
    iptables -t nat -A PREROUTING -p udp -m udp --dport $port_range -j DNAT --to-destination $target_ip:$port_range

    echo "保存 iptables 设置..."
    service iptables save

    echo "转发设置已完成!"
}

while true; do
    display_menu
    read -p "请输入选项 (1, 2 或 3): " choice
    case $choice in
        1)
            setup_iptables
            read -p "按任意键继续..." key
            ;;
        2)
            configure_nat
            read -p "按任意键继续..." key
            ;;
        3)
            echo "退出脚本..."
            exit 0
            ;;
        *)
            echo "无效的选项。请输入 1, 2 或 3。"
            read -p "按任意键继续..." key
            ;;
    esac
done
