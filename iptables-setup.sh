#!/bin/bash

# Script for setting up IP forwarding and iptables configuration.

function display_menu {
    clear
    echo "腳本由 BYY 設計"
    echo "WeChat: x7077796"
    echo "============================"
    echo "選擇要執行的操作："
    echo "1. 執行事前準備和安裝"
    echo "2. 設定轉發"
    echo "3. 退出"
    echo "============================"
}

function setup_iptables {
    echo "更新系統..."
    yum update -y
    systemctl stop firewalld
    systemctl disable firewalld
    yum install iptables-services -y
    systemctl enable iptables
    systemctl start iptables

    echo "設定 IP 轉發..."
    echo "#. Controls IP packet forwarding" >> /etc/sysctl.conf
    echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
    sysctl -p

    echo "事前準備和安裝已完成!"
}

function configure_nat {
    read -p "請輸入需要中轉的外部 IP: " target_ip
    read -p "請輸入TCP/UDP端口範圍 (例如 10000-10002): " port_range

    echo "獲取內網 IP 地址..."
    internal_ip=$(ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    echo "檢測到的內網 IP 地址: $internal_ip"

    echo "設定 iptables 轉發規則..."
    iptables -t nat -A POSTROUTING -d $target_ip -p tcp -m tcp --dport $port_range -j SNAT --to-source $internal_ip
    iptables -t nat -A POSTROUTING -d $target_ip -p udp -m udp --dport $port_range -j SNAT --to-source $internal_ip
    iptables -t nat -A PREROUTING -p tcp -m tcp --dport $port_range -j DNAT --to-destination $target_ip:$port_range
    iptables -t nat -A PREROUTING -p udp -m udp --dport $port_range -j DNAT --to-destination $target_ip:$port_range

    echo "保存 iptables 設定..."
    service iptables save

    echo "轉發設定已完成!"
}

while true; do
    display_menu
    read -p "請輸入選項 (1, 2 或 3): " choice
    case $choice in
        1)
            setup_iptables
            read -p "按任意鍵繼續..." key
            ;;
        2)
            configure_nat
            read -p "按任意鍵繼續..." key
            ;;
        3)
            echo "退出腳本..."
            exit 0
            ;;
        *)
            echo "無效的選項。請輸入 1, 2 或 3。"
            read -p "按任意鍵繼續..." key
            ;;
    esac
done
