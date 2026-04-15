#!/bin/bash

# ================= 颜色设置 =================
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
PURPLE='\033[0;35m'  # 新增高贵紫色，用于您的专属签名
NC='\033[0m'

# ================= 致命防呆 1：检查是否为 Root 权限 =================
if [[ $EUID -ne 0 ]]; then
   clear
   echo -e "${RED}❌ 哎呀！权限不够哦！${NC}"
   echo -e "这个脚本需要系统的最高权限才能运行。"
   echo -e "👉 请输入 ${YELLOW}sudo su${NC} 命令回车，切换到 root 账号后再运行我吧！"
   exit 1
fi

# ================= 自动环境与依赖检查 (全静默防吓人) =================
if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    sysctl -p >/dev/null 2>&1
fi

if ! command -v iptables &> /dev/null; then
    yum install -q -y iptables-services >/dev/null 2>&1
    systemctl enable --now iptables >/dev/null 2>&1
fi

if ! command -v wget &> /dev/null; then yum install -q -y wget >/dev/null 2>&1; fi
if ! command -v gzip &> /dev/null; then yum install -q -y gzip >/dev/null 2>&1; fi

if ! command -v gost &> /dev/null; then
    clear
    echo -e "${YELLOW}🎁 首次运行，正在后台悄悄帮您下载必须的组件，请耐心稍等几秒钟...${NC}"
    wget -q -O gost.gz https://github.com/ginuerzh/gost/releases/download/v2.11.5/gost-linux-amd64-2.11.5.gz
    gzip -d gost.gz
    chmod +x gost
    mv gost /usr/local/bin/
fi

# ================= 致命防呆 2：端口数字验证函数 =================
check_port() {
    if ! [[ "$1" =~ ^[0-9]+$ ]] || [ "$1" -lt 1 ] || [ "$1" -gt 65535 ]; then
        echo -e "${RED}❌ 填错啦！端口只能是 1 到 65535 之间的纯数字哦！已取消。${NC}"
        sleep 2
        return 1
    fi
    return 0
}

# ================= 主菜单循环 =================
while true; do
    clear
    IPTABLES_COUNT=$(iptables -t nat -L PREROUTING -n 2>/dev/null | grep "dpt:" | wc -l)
    GOST_COUNT=$(ls /etc/systemd/system/gost-*.service 2>/dev/null | wc -l)
    
    # --- 您的专属尊享版菜单排版 ---
    echo -e "${CYAN}====================================================${NC}"
    echo -e "${YELLOW}       🎮 游戏工作室专属 - 网络中转管理系统 🎮      ${NC}"
    echo -e "${CYAN}====================================================${NC}"
    echo -e " ${GREEN}运行状态：${NC}简单直连 ${YELLOW}${IPTABLES_COUNT}${NC} 条 | 加密隧道 ${YELLOW}${GOST_COUNT}${NC} 条"
    echo -e "${CYAN}----------------------------------------------------${NC}"
    echo -e "${GREEN}  1. 🟢 [新手推荐] 新增“简单直连” (单台服务器就能用)${NC}"
    echo -e "${RED}  2. 🔴 [进阶防封] 架设“加密隧道” (国内+海外双机配合)${NC}"
    echo -e "${CYAN}----------------------------------------------------${NC}"
    echo -e "  3. 📋 查看运行状态 (看看当前都在转发哪些端口)"
    echo -e "  4. 🗑️ 删除或清空规则 (设置错了 / 不想玩了点这里)"
    echo -e "  5. ⚡ 一键防断线优化 (降低延迟，挂机必备，强烈推荐)"
    echo -e "  0. 🚪 退出脚本"
    echo -e "${CYAN}====================================================${NC}"
    echo -e "${PURPLE}  👨‍💻 脚本由 BYY 设计 - 2026 最终完美版${NC}"
    echo -e "${PURPLE}  💬 官方微信 (WeChat): x7077796${NC}"
    echo -e "${CYAN}====================================================${NC}"
    echo ""
    read -p "请输入对应的数字 [0-5]: " choice

    case $choice in
        1)
            echo -e "\n${CYAN}--- 🟢 简单直连 (单机模式) ---${NC}"
            echo "说明：适合网络没有被墙的情况。你电脑上的软件（如辅助、代理客户端）连这台机器，这台机器帮你把流量转走。"
            echo "----------------------------------------------------"
            
            read -p "步骤 1/3：【你的电脑软件】要连这台机器的哪个端口？ (比如填 8080): " local_port
            if [ -z "$local_port" ]; then echo -e "${RED}❌ 端口不能空着不填哦！已取消。${NC}"; sleep 1.5; continue; fi 
            if ! check_port "$local_port"; then continue; fi
            
            read -p "步骤 2/3：最终的【目标机器 IP】是多少？ (比如你的 Socks5/代理节点 IP): " remote_ip
            if [ -z "$remote_ip" ]; then echo -e "${RED}❌ IP不能空着不填哦！已取消。${NC}"; sleep 1.5; continue; fi
            
            read -p "步骤 3/3：最终的【目标机器 端口】是多少？ (比如 Socks5 的端口): " remote_port
            if [ -z "$remote_port" ]; then echo -e "${RED}❌ 端口不能空着不填哦！已取消。${NC}"; sleep 1.5; continue; fi
            if ! check_port "$remote_port"; then continue; fi

            iptables -t nat -A PREROUTING -p tcp --dport $local_port -j DNAT --to-destination $remote_ip:$remote_port
            iptables -t nat -A POSTROUTING -p tcp -d $remote_ip --dport $remote_port -j MASQUERADE
            iptables -t nat -A PREROUTING -p udp --dport $local_port -j DNAT --to-destination $remote_ip:$remote_port
            iptables -t nat -A POSTROUTING -p udp -d $remote_ip --dport $remote_port -j MASQUERADE
            service iptables save > /dev/null 2>&1
            
            echo -e "\n${GREEN}🎉 搞定！设置成功！${NC}"
            echo -e "现在去把你【电脑上的软件或代理客户端】里面的连接 IP 改成【这台机器的 IP】，端口填【$local_port】就可以连上了！"
            read -p "按回车键 (Enter) 返回主菜单..." 
            ;;
            
        2)
            clear
            echo -e "${CYAN}====================================================${NC}"
            echo -e "${RED}        🔴 高级加密隧道 (双机防封模式) 🔴          ${NC}"
            echo -e "${CYAN}====================================================${NC}"
            echo -e "这个模式需要两台机器打配合，请严格按照以下顺序操作："
            echo -e "👉 ${YELLOW}第一步：先登录你的「海外机」运行本脚本，选择 A 搭建接收端。${NC}"
            echo -e "👉 ${YELLOW}第二步：再登录你的「国内机」运行本脚本，选择 B 连接海外机。${NC}"
            echo "----------------------------------------------------"
            echo "请问你【现在正在操作】的是哪一台机器？"
            echo "  A) 🌍 这是【海外机】(负责接收国内流量，并真正去连接代理节点)"
            echo "  B) 🏠 这是【国内机】(负责伪装流量，你的电脑软件直接连这台)"
            echo "  0) 🔙 哎呀点错了，退回上一步"
            echo "----------------------------------------------------"
            read -p "请输入字母 A 或 B (大小写都可以): " role_choice
            
            if [[ "$role_choice" == "A" || "$role_choice" == "a" ]]; then
                echo -e "\n${CYAN}--- 🌍 开始设置海外接收端 ---${NC}"
                read -p "步骤 1/2：请设置一个隧道【监听端口】 (推荐填 443，直接回车默认443): " tunnel_port
                if [ -z "$tunnel_port" ]; then tunnel_port=443; fi
                if ! check_port "$tunnel_port"; then continue; fi
                
                read -p "步骤 2/2：请设置一个隧道【连接密码】 (随便填，比如 123456，防止别人蹭网): " tunnel_pass
                if [ -z "$tunnel_pass" ]; then echo -e "${RED}❌ 密码不能空着不填哦！已取消。${NC}"; sleep 1.5; continue; fi
                
                SERVICE_NAME="gost-server-${tunnel_port}"
                cat <<EOF > /etc/systemd/system/${SERVICE_NAME}.service
[Unit]
Description=GOST Tunnel Server on port ${tunnel_port}
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/gost -L relay+tls://admin:${tunnel_pass}@:${tunnel_port}
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF
                systemctl daemon-reload && systemctl enable --now ${SERVICE_NAME}
                echo -e "\n${GREEN}🎉 海外机设置完毕！程序已经在后台默默守护运行了。${NC}"
                echo -e "⚠️ 请把下面这两行信息记下来，等一下去设置国内机的时候要用到："
                echo -e "   - 隧道端口: ${YELLOW}$tunnel_port${NC}"
                echo -e "   - 隧道密码: ${YELLOW}$tunnel_pass${NC}"
                
            elif [[ "$role_choice" == "B" || "$role_choice" == "b" ]]; then
                echo -e "\n${CYAN}--- 🏠 开始设置国内转发端 ---${NC}"
                echo "请务必确认你已经把海外机(选A的那步)设置好了！"
                
                read -p "步骤 1/6：【你的电脑软件】要连这台国内机的【哪个端口】? (比如填 8080): " local_port
                if [ -z "$local_port" ]; then echo -e "${RED}❌ 填空不能留白哦！已取消。${NC}"; sleep 1; continue; fi
                if ! check_port "$local_port"; then continue; fi
                
                read -p "步骤 2/6：最终的【目标机器 IP】是多少? (比如你的代理节点或Socks5的IP): " game_ip
                if [ -z "$game_ip" ]; then echo -e "${RED}❌ 填空不能留白哦！已取消。${NC}"; sleep 1; continue; fi
                
                read -p "步骤 3/6：最终的【目标机器 端口】是多少? (比如代理节点的端口): " game_port
                if [ -z "$game_port" ]; then echo -e "${RED}❌ 填空不能留白哦！已取消。${NC}"; sleep 1; continue; fi
                if ! check_port "$game_port"; then continue; fi
                
                read -p "步骤 4/6：你刚刚设置好的【海外机 IP】是多少? (海外服务器的公网IP): " remote_ip
                if [ -z "$remote_ip" ]; then echo -e "${RED}❌ 填空不能留白哦！已取消。${NC}"; sleep 1; continue; fi
                
                read -p "步骤 5/6：刚刚在海外机设置的【隧道端口】是多少? (通常是 443): " remote_port
                if [ -z "$remote_port" ]; then echo -e "${RED}❌ 填空不能留白哦！已取消。${NC}"; sleep 1; continue; fi
                if ! check_port "$remote_port"; then continue; fi
                
                read -p "步骤 6/6：刚刚在海外机设置的【隧道密码】是什么?: " tunnel_pass
                if [ -z "$tunnel_pass" ]; then echo -e "${RED}❌ 填空不能留白哦！已取消。${NC}"; sleep 1; continue; fi

                SERVICE_NAME="gost-client-${local_port}"
                cat <<EOF > /etc/systemd/system/${SERVICE_NAME}.service
[Unit]
Description=GOST Game Forwarding on local port ${local_port}
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/gost -L tcp://:${local_port}/${game_ip}:${game_port} -L udp://:${local_port}/${game_ip}:${game_port} -F relay+tls://admin:${tunnel_pass}@${remote_ip}:${remote_port}
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF
                systemctl daemon-reload && systemctl enable --now ${SERVICE_NAME}
                echo -e "\n${GREEN}🎉 国内机设置完毕！加密隧道已经顺利打通。${NC}"
                echo -e "现在去把你【电脑上的软件或代理客户端】里面的连接 IP 改成【这台国内机的 IP】，端口填【$local_port】，就可以安心防封啦！"
                
            elif [[ "$role_choice" == "0" ]]; then
                continue 
            else
                echo -e "${RED}❌ 别乱按呀，请输入字母 A 或 B。${NC}"
                sleep 1.5
            fi
            read -p "按回车键 (Enter) 返回主菜单..." 
            ;;
            
        3)
            echo -e "\n${CYAN}--- 📋 运行状态一览 ---${NC}"
            echo -e "${YELLOW}【简单直连规则 (iptables)】${NC}"
            iptables -t nat -nL PREROUTING --line-numbers 2>/dev/null | grep "^[0-9]" | awk '{print "  ["$4"] 端口 "$7" -> "$8}' | sed 's/dpt://g' | sed 's/to://g'
            if [ $(iptables -t nat -L PREROUTING -n 2>/dev/null | grep -c "dpt:") -eq 0 ]; then echo "  (目前没有设置)"; fi
            
            echo -e "\n${YELLOW}【高级加密隧道 (GOST)】${NC}"
            ls /etc/systemd/system/gost-*.service 2>/dev/null | while read file; do
                svc=$(basename "$file")
                status=$(systemctl is-active "$svc")
                if [ "$status" == "active" ]; then
                    echo -e "  ${GREEN}[运行中正常]${NC} $svc"
                else
                    echo -e "  ${RED}[已停止或异常]${NC} $svc"
                fi
            done
            if [ $(ls /etc/systemd/system/gost-*.service 2>/dev/null | wc -l) -eq 0 ]; then echo "  (目前没有设置)"; fi
            read -p "按回车键 (Enter) 返回主菜单..."
            ;;
            
        4)
            echo -e "\n${CYAN}--- 🗑️ 删除或清空规则 ---${NC}"
            echo "1. 💥 一键清空所有【简单直连】规则"
            echo "2. 🎯 针对性删除指定的【高级加密隧道】"
            read -p "请选择你要清理的项目 (填 1 或 2，按其他键取消): " del_choice
            
            if [ "$del_choice" == "1" ]; then
                iptables -t nat -F
                iptables -t nat -X
                service iptables save > /dev/null 2>&1
                echo -e "${GREEN}✅ 搞定，所有的简单直连规则都被清空了。${NC}"
            elif [ "$del_choice" == "2" ]; then
                echo -e "\n目前存在的高级隧道服务有："
                ls /etc/systemd/system/gost-*.service 2>/dev/null | xargs -n 1 basename
                read -p "📝 请复制上面的完整名字贴在这里 (例如 gost-client-8080.service): " del_svc
                if [ -f "/etc/systemd/system/$del_svc" ]; then
                    systemctl stop "$del_svc"
                    systemctl disable "$del_svc"
                    rm -f "/etc/systemd/system/$del_svc"
                    systemctl daemon-reload
                    echo -e "${GREEN}✅ $del_svc 已经被彻底删除了。${NC}"
                else
                    echo -e "${RED}找不到这个名字，请确认一下有没有少复制字母哦。${NC}"
                fi
            fi
            read -p "按回车键 (Enter) 返回主菜单..."
            ;;
            
        5)
            echo -e "\n${CYAN}--- ⚡ 正在应用网络底层优化 ---${NC}"
            sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
            sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
            echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
            echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
            
            sed -i '/net.ipv4.tcp_tw_reuse/d' /etc/sysctl.conf
            sed -i '/net.ipv4.tcp_keepalive_time/d' /etc/sysctl.conf
            sed -i '/net.ipv4.tcp_max_syn_backlog/d' /etc/sysctl.conf
            echo "net.ipv4.tcp_tw_reuse=1" >> /etc/sysctl.conf
            echo "net.ipv4.tcp_keepalive_time=600" >> /etc/sysctl.conf
            echo "net.ipv4.tcp_max_syn_backlog=8192" >> /etc/sysctl.conf
            sysctl -p >/dev/null 2>&1
            echo -e "${GREEN}✅ 成了！系统防断线和 BBR 加速已经开启，连接更稳定。${NC}"
            read -p "按回车键 (Enter) 返回主菜单..."
            ;;
            
        0)
            echo -e "${GREEN}感谢使用，祝老板财源广进！拜拜。${NC}"
            break
            ;;
            
        *)
            echo -e "${RED}❌ 看错了吧，请输入菜单上有的数字 (0-5) 哦！${NC}"
            sleep 1
            ;;
    esac
done
