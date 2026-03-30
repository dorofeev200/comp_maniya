#!/bin/bash

# ===============================
# COMP_MANIYA KASKAD INSTALLER
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
        echo -e "${RED}Ошибка: запустите от root${NC}"
        exit 1
    fi
}

prepare_system() {
    apt-get update -y > /dev/null
    apt-get install -y iptables-persistent netfilter-persistent qrencode curl > /dev/null

    sysctl -w net.ipv4.ip_forward=1 >/dev/null

    grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf || \
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
}

show_promo() {
    clear
    echo -e "${MAGENTA}====================================================${NC}"
    echo -e "${GREEN}              COMP_MANIYA KASKAD PRO${NC}"
    echo -e "${CYAN}Telegram: https://t.me/computerchik${NC}"
    echo -e "${RED}YouTube: https://www.youtube.com/@comp_maniya${NC}"
    echo -e "${MAGENTA}====================================================${NC}"
    echo ""

    echo -e "${YELLOW}QR Telegram:${NC}"
    qrencode -t ANSIUTF8 "https://t.me/computerchik"

    echo ""
    echo -e "${YELLOW}QR YouTube:${NC}"
    qrencode -t ANSIUTF8 "https://www.youtube.com/@comp_maniya"

    echo ""
    read -p "Нажмите Enter..."
}

create_cascade() {
    clear
    echo -e "${CYAN}Создание каскадного правила${NC}"
    echo ""

    read -p "Протокол (tcp/udp): " PROTO
    read -p "IP удаленного сервера: " TARGET_IP
    read -p "Входящий порт: " IN_PORT
    read -p "Исходящий порт: " OUT_PORT

    iptables -A INPUT -p "$PROTO" --dport "$IN_PORT" -j ACCEPT
    iptables -t nat -A PREROUTING -p "$PROTO" --dport "$IN_PORT" -j DNAT --to-destination "$TARGET_IP:$OUT_PORT"
    iptables -t nat -A POSTROUTING -j MASQUERADE
    iptables -A FORWARD -p "$PROTO" -d "$TARGET_IP" --dport "$OUT_PORT" -j ACCEPT

    netfilter-persistent save > /dev/null

    echo ""
    echo -e "${GREEN}Каскад успешно создан${NC}"
    echo -e "${WHITE}$PROTO : $IN_PORT -> $TARGET_IP:$OUT_PORT${NC}"
    echo ""
    read -p "Нажмите Enter..."
}

show_rules() {
    clear
    echo -e "${CYAN}Активные правила:${NC}"
    echo ""
    iptables -t nat -L -n -v
    echo ""
    read -p "Нажмите Enter..."
}

flush_rules() {
    clear
    echo -e "${RED}ВНИМАНИЕ! Удалить ВСЕ правила?${NC}"
    read -p "Подтвердите (y/n): " confirm

    if [[ "$confirm" == "y" ]]; then
        iptables -F
        iptables -t nat -F
        iptables -X
        netfilter-persistent save > /dev/null
        echo -e "${GREEN}Все правила удалены${NC}"
    fi

    read -p "Нажмите Enter..."
}

show_menu() {
    while true; do
        clear
        echo -e "${GREEN}==============================================${NC}"
        echo -e "${GREEN}             COMP_MANIYA MENU${NC}"
        echo -e "${GREEN}==============================================${NC}"
        echo -e "${CYAN}Telegram: https://t.me/computerchik${NC}"
        echo -e "${RED}YouTube: https://www.youtube.com/@comp_maniya${NC}"
        echo ""
        echo "1) Создать каскад"
        echo "2) Показать QR и ссылки"
        echo "3) Показать активные правила"
        echo "4) Удалить все правила"
        echo "0) Выход"
        echo ""

        read -p "Выбор: " choice

        case $choice in
            1) create_cascade ;;
            2) show_promo ;;
            3) show_rules ;;
            4) flush_rules ;;
            0) exit 0 ;;
            *) ;;
        esac
    done
}

check_root
prepare_system
show_menu
