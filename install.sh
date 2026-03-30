#!/bin/bash

# ===============================
# COMP_MANIYA FULL KASKAD PRO
# Telegram: https://t.me/computerchik
# YouTube: https://www.youtube.com/@comp_maniya
# ===============================

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
BLUE='\033[0;34m'
NC='\033[0m'

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}[ERROR] Запустите от root${NC}"
        exit 1
    fi
}

prepare_system() {
    if [ "$0" != "/usr/local/bin/compmaniya" ]; then
        cp -f "$0" "/usr/local/bin/compmaniya"
        chmod +x "/usr/local/bin/compmaniya"
    fi

    export DEBIAN_FRONTEND=noninteractive

    apt-get update -y > /dev/null
    apt-get install -y iptables-persistent netfilter-persistent qrencode > /dev/null

    grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf || \
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

    grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf || \
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf

    grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf || \
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf

    sysctl -p > /dev/null
}

show_promo() {
    clear
    echo ""
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║                 COMP_MANIYA KASKAD PRO                     ║${NC}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    echo -e "${CYAN}Telegram:${NC} https://t.me/computerchik"
    echo -e "${RED}YouTube:${NC} https://www.youtube.com/@comp_maniya"

    echo ""
    echo -e "${YELLOW}QR Telegram:${NC}"
    qrencode -t ANSIUTF8 "https://t.me/computerchik"

    echo ""
    echo -e "${YELLOW}QR YouTube:${NC}"
    qrencode -t ANSIUTF8 "https://www.youtube.com/@comp_maniya"

    echo ""
    read -p "Нажмите Enter..."
}

show_instructions() {
    clear
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║                    ИНСТРУКЦИЯ ПО КАСКАДУ                   ║${NC}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    echo -e "${CYAN}1. Выберите нужный тип подключения${NC}"
    echo -e "${CYAN}2. Введите IP конечного сервера${NC}"
    echo -e "${CYAN}3. Укажите входящий и исходящий порт${NC}"
    echo -e "${CYAN}4. Подключайте клиентов к этому VPS${NC}"
    echo ""
    read -p "Нажмите Enter..."
}

apply_iptables_rules() {
    local PROTO=$1
    local IN_PORT=$2
    local OUT_PORT=$3
    local TARGET_IP=$4
    local NAME=$5

    IFACE=$(ip route get 8.8.8.8 | awk '{print $5}')

    iptables -A INPUT -p "$PROTO" --dport "$IN_PORT" -j ACCEPT
    iptables -t nat -A PREROUTING -p "$PROTO" --dport "$IN_PORT" -j DNAT --to-destination "$TARGET_IP:$OUT_PORT"

    if ! iptables -t nat -C POSTROUTING -o "$IFACE" -j MASQUERADE 2>/dev/null; then
        iptables -t nat -A POSTROUTING -o "$IFACE" -j MASQUERADE
    fi

    iptables -A FORWARD -p "$PROTO" -d "$TARGET_IP" --dport "$OUT_PORT" -j ACCEPT

    netfilter-persistent save > /dev/null

    echo -e "${GREEN}[SUCCESS] $NAME настроен${NC}"
    echo "$PROTO: $IN_PORT -> $TARGET_IP:$OUT_PORT"
    read -p "Нажмите Enter..."
}

configure_rule() {
    local PROTO=$1
    local NAME=$2

    echo ""
    read -p "IP назначения: " TARGET_IP
    read -p "Порт: " PORT

    apply_iptables_rules "$PROTO" "$PORT" "$PORT" "$TARGET_IP" "$NAME"
}

configure_custom_rule() {
    echo ""
    read -p "Протокол (tcp/udp): " PROTO
    read -p "IP назначения: " TARGET_IP
    read -p "Входящий порт: " IN_PORT
    read -p "Исходящий порт: " OUT_PORT

    apply_iptables_rules "$PROTO" "$IN_PORT" "$OUT_PORT" "$TARGET_IP" "Custom Rule"
}

list_active_rules() {
    clear
    echo -e "${CYAN}Активные правила:${NC}"
    iptables -t nat -L -n -v
    echo ""
    read -p "Нажмите Enter..."
}

delete_single_rule() {
    clear
    echo -e "${RED}Удаление одного правила пока в разработке${NC}"
    read -p "Нажмите Enter..."
}

flush_rules() {
    clear
    echo -e "${RED}СБРОС ВСЕХ ПРАВИЛ${NC}"
    read -p "Подтвердить (y/n): " confirm

    if [[ "$confirm" == "y" ]]; then
        iptables -F
        iptables -t nat -F
        iptables -X
        netfilter-persistent save > /dev/null
    fi

    read -p "Нажмите Enter..."
}

show_menu() {
    while true; do
        clear
        echo -e "${MAGENTA}"
        echo "******************************************************"
        echo "           COMP_MANIYA KASKAD PRO"
        echo "   YouTube: https://www.youtube.com/@comp_maniya"
        echo "   Telegram: https://t.me/computerchik"
        echo "******************************************************"
        echo -e "${NC}"

        echo -e "1) Настроить ${CYAN}AmneziaWG / WireGuard${NC} (UDP)"
        echo -e "2) Настроить ${CYAN}VLESS / XRay${NC} (TCP)"
        echo -e "3) Настроить ${CYAN}MTProto / TProxy${NC} (TCP)"
        echo -e "4) 🛠 Создать ${YELLOW}Кастомное правило${NC}"
        echo -e "5) Посмотреть активные правила"
        echo -e "6) Удалить одно правило"
        echo -e "7) ${RED}Сбросить ВСЕ настройки${NC}"
        echo -e "8) Показать мои каналы"
        echo -e "9) 📚 Инструкция"
        echo -e "0) Выход"
        echo ""
        read -p "Ваш выбор: " choice

        case $choice in
            1) configure_rule "udp" "AmneziaWG" ;;
            2) configure_rule "tcp" "VLESS / XRay" ;;
            3) configure_rule "tcp" "MTProto" ;;
            4) configure_custom_rule ;;
            5) list_active_rules ;;
            6) delete_single_rule ;;
            7) flush_rules ;;
            8) show_promo ;;
            9) show_instructions ;;
            0) exit 0 ;;
        esac
    done
}

check_root
prepare_system
show_promo
show_menu
