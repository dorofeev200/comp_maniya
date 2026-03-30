#!/bin/bash

# ===============================
# COMP_MANIYA FULL KASKAD PRO
# Telegram: https://t.me/computerchik
# YouTube: https://www.youtube.com/@comp_maniya
# ===============================

# --- ЦВЕТА ---
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ---

type_text() {
    local text="$1"
    local delay=0.03
    for (( i=0; i<${#text}; i++ )); do
        echo -n "${text:$i:1}"
        sleep $delay
    done
    echo ""
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}[ERROR] Запустите скрипт с правами root!${NC}"
        exit 1
    fi
}

# --- ПОДГОТОВКА СИСТЕМЫ ---
prepare_system() {
    # Автоматическое создание глобальной команды compmaniya
    if [ "$0" != "/usr/local/bin/compmaniya" ]; then
        cp -f "$0" "/usr/local/bin/compmaniya"
        chmod +x "/usr/local/bin/compmaniya"
    fi

    # Включение IP Forwarding
    if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf; then
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    else
        sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
    fi

    # Активация Google BBR
    if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf; then
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    fi
    if ! grep -q "net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf; then
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    fi
    sysctl -p > /dev/null

    # Установка зависимостей
    export DEBIAN_FRONTEND=noninteractive
    if ! dpkg -s iptables-persistent >/dev/null 2>&1; then
        apt-get update -y > /dev/null
        apt-get install -y iptables-persistent netfilter-persistent qrencode > /dev/null
    fi
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
    read -p "Нажмите enter для настройки каскадного скрипта..."
}

# --- ИНСТРУКЦИЯ (ТЕКСТ ВНУТРИ КОДА) ---
show_instructions() {
    clear
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║             📚 ИНСТРУКЦИЯ: КАК НАСТРОИТЬ КАСКАД              ║${NC}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}ШАГ 1: Подготовка${NC}"
    echo -e "У вас должны быть данные от зарубежного сервера (VPN/Прокси и т.д.):"
    echo -e " - ${YELLOW}IP адрес${NC} (зарубежный)"
    echo -e " - ${YELLOW}Порт${NC} (на котором работает целевой сервис)"
    echo ""
    echo -e "${CYAN}ШАГ 2: Настройка этого сервера${NC}"
    echo -e "1. Выберите нужный пункт (${GREEN}1-3${NC} для стандартных или ${GREEN}4${NC} для кастомных)."
    echo -e "2. Введите ${YELLOW}IP${NC} и ${YELLOW}Порты${NC} (входящий и исходящий)."
    echo -e "3. Скрипт создаст 'мост' через этот VPS."
    echo ""
    echo -e "${CYAN}ШАГ 3: Настройка Клиента (Важно!)${NC}"
    echo -e "1. Откройте приложение клиента."
    echo -e "2. В настройках соединения найдите поле ${YELLOW}Endpoint / Адрес сервера${NC}."
    echo -e "3. Замените зарубежный IP на ${GREEN}IP ЭТОГО СЕРВЕРА${NC}."
    echo -e "4. Если вы использовали разные порты в правиле №4, укажите Входящий порт."
    echo ""
    echo -e "${GREEN}Готово! Теперь трафик идет: Клиент -> Этот Сервер -> Зарубеж.${NC}"
    echo ""
    read -p "Нажмите Enter, чтобы вернуться в меню..."
}

# --- СТАНДАРТНАЯ НАСТРОЙКА (ПОРТ ВХОДА = ПОРТ ВЫХОДА) ---
configure_rule() {
    local PROTO=$1
    local NAME=$2

    echo -e "\n${CYAN}--- Настройка $NAME ($PROTO) ---${NC}"

    while true; do
        echo -e "Введите IP адрес назначения:"
        read -p "> " TARGET_IP
        if [[ -n "$TARGET_IP" ]]; then break; fi
    done

    while true; do
        echo -e "Введите Порт (одинаковый для входа и выхода):"
        read -p "> " PORT
        if [[ "$PORT" =~ ^[0-9]+$ ]] && [ "$PORT" -le 65535 ]; then break; fi
        echo -e "${RED}Ошибка: порт должен быть числом!${NC}"
    done

    apply_iptables_rules "$PROTO" "$PORT" "$PORT" "$TARGET_IP" "$NAME"
}

# --- КАСТОМНАЯ НАСТРОЙКА (РАЗНЫЕ ПОРТЫ) ---
configure_custom_rule() {
    echo -e "\n${CYAN}--- 🛠 Универсальное кастомное правило ---${NC}"
    echo -e "${WHITE}Подходит для перенаправления ЛЮБЫХ протоколов (SSH, RDP, нестандартные порты)."
    echo -e "Позволяет сделать так, чтобы клиент подключался к одному порту,"
    echo -e "а трафик уходил на другой порт зарубежного сервера.${NC}\n"

    while true; do
        echo -e "Выберите протокол (${YELLOW}tcp${NC} или ${YELLOW}udp${NC}):"
        read -p "> " PROTO
        if [[ "$PROTO" == "tcp" || "$PROTO" == "udp" ]]; then break; fi
        echo -e "${RED}Ошибка: введите tcp или udp!${NC}"
    done

    while true; do
        echo -e "Введите IP адрес назначения (куда отправляем трафик):"
        read -p "> " TARGET_IP
        if [[ -n "$TARGET_IP" ]]; then break; fi
    done

    while true; do
        echo -e "Введите ${YELLOW}ВХОДЯЩИЙ Порт${NC} (на этом сервере):"
        read -p "> " IN_PORT
        if [[ "$IN_PORT" =~ ^[0-9]+$ ]] && [ "$IN_PORT" -le 65535 ]; then break; fi
        echo -e "${RED}Ошибка: порт должен быть числом!${NC}"
    done

    while true; do
        echo -e "Введите ${YELLOW}ИСХОДЯЩИЙ Порт${NC} (на конечном сервере):"
        read -p "> " OUT_PORT
        if [[ "$OUT_PORT" =~ ^[0-9]+$ ]] && [ "$OUT_PORT" -le 65535 ]; then break; fi
        echo -e "${RED}Ошибка: порт должен быть числом!${NC}"
    done

    apply_iptables_rules "$PROTO" "$IN_PORT" "$OUT_PORT" "$TARGET_IP" "Custom Rule"
}

# --- ПРИМЕНЕНИЕ ПРАВИЛ IPTABLES ---
apply_iptables_rules() {
    local PROTO=$1
    local IN_PORT=$2
    local OUT_PORT=$3
    local TARGET_IP=$4
    local NAME=$5

    IFACE=$(ip route get 8.8.8.8 | awk -- '{printf $5}')
    if [[ -z "$IFACE" ]]; then
        echo -e "${RED}[ERROR] Не удалось определить интерфейс!${NC}"
        exit 1
    fi

    echo -e "${YELLOW}[*] Применение правил...${NC}"

    # Удаление старых правил (по входящему порту)
    iptables -t nat -D PREROUTING -p "$PROTO" --dport "$IN_PORT" -j DNAT --to-destination "$TARGET_IP:$OUT_PORT" 2>/dev/null
    iptables -D INPUT -p "$PROTO" --dport "$IN_PORT" -j ACCEPT 2>/dev/null
    iptables -D FORWARD -p "$PROTO" -d "$TARGET_IP" --dport "$OUT_PORT" -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT 2>/dev/null
    iptables -D FORWARD -p "$PROTO" -s "$TARGET_IP" --sport "$OUT_PORT" -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null

    # Новые правила
    iptables -A INPUT -p "$PROTO" --dport "$IN_PORT" -j ACCEPT
    iptables -t nat -A PREROUTING -p "$PROTO" --dport "$IN_PORT" -j DNAT --to-destination "$TARGET_IP:$OUT_PORT"
    
    if ! iptables -t nat -C POSTROUTING -o "$IFACE" -j MASQUERADE 2>/dev/null; then
        iptables -t nat -A POSTROUTING -o "$IFACE" -j MASQUERADE
    fi

    iptables -A FORWARD -p "$PROTO" -d "$TARGET_IP" --dport "$OUT_PORT" -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
    iptables -A FORWARD -p "$PROTO" -s "$TARGET_IP" --sport "$OUT_PORT" -m state --state ESTABLISHED,RELATED -j ACCEPT

    # Настройка UFW если активен
    if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
        ufw allow "$IN_PORT"/"$PROTO" >/dev/null
        sed -i 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw
        ufw reload >/dev/null
    fi

    netfilter-persistent save > /dev/null
    
    echo -e "${GREEN}[SUCCESS] $NAME настроен!${NC}"
    echo -e "$PROTO: Вход $IN_PORT -> Выход $TARGET_IP:$OUT_PORT"
    read -p "Нажмите Enter для возврата в меню..."
}

# --- СПИСОК ПРАВИЛ ---
list_active_rules() {
    echo -e "\n${CYAN}--- Активные переадресации ---${NC}"
    echo -e "${MAGENTA}ПОРТ (ВХОД)\tПРОТОКОЛ\tЦЕЛЬ (IP:ВЫХОД)${NC}"
    iptables -t nat -S PREROUTING | grep "DNAT" | while read -r line ; do
        l_port=$(echo "$line" | grep -oP '(?<=--dport )\d+')
        l_proto=$(echo "$line" | grep -oP '(?<=-p )\w+')
        l_dest=$(echo "$line" | grep -oP '(?<=--to-destination )[\d\.:]+')
        if [[ -n "$l_port" ]]; then echo -e "$l_port\t\t$l_proto\t\t$l_dest"; fi
    done
    echo ""
    
    echo -e "${GREEN}💰 Задонатить каналу и автору:${NC}"
    if command -v qrencode &> /dev/null; then
        qrencode -t ANSIUTF8 "https://pay.cloudtips.ru/p/4a618628"
    else
        echo "https://pay.cloudtips.ru/p/4a618628"
    fi
    echo ""

    read -p "Нажмите Enter..."
}

# --- УДАЛЕНИЕ ОДНОГО ПРАВИЛА ---
delete_single_rule() {
    echo -e "\n${CYAN}--- Удаление правила ---${NC}"
    declare -a RULES_LIST
    local i=1
    while read -r line; do
        l_port=$(echo "$line" | grep -oP '(?<=--dport )\d+')
        l_proto=$(echo "$line" | grep -oP '(?<=-p )\w+')
        l_dest=$(echo "$line" | grep -oP '(?<=--to-destination )[\d\.:]+')
        if [[ -n "$l_port" ]]; then
            RULES_LIST[$i]="$l_port:$l_proto:$l_dest"
            echo -e "${YELLOW}[$i]${NC} Вход: $l_port ($l_proto) -> Выход: $l_dest"
            ((i++))
        fi
    done < <(iptables -t nat -S PREROUTING | grep "DNAT")

    if [ ${#RULES_LIST[@]} -eq 0 ]; then
        echo -e "${RED}Нет активных правил.${NC}"
        read -p "Нажмите Enter..."
        return
    fi

    echo ""
    read -p "Номер правила для удаления (0 отмена): " rule_num
    if [[ "$rule_num" == "0" || -z "${RULES_LIST[$rule_num]}" ]]; then return; fi

    # Разбираем строку
    IFS=':' read -r d_port d_proto d_dest <<< "${RULES_LIST[$rule_num]}"
    local target_ip="${d_dest%:*}"
    local target_port="${d_dest#*:}"
    
    iptables -t nat -D PREROUTING -p "$d_proto" --dport "$d_port" -j DNAT --to-destination "$d_dest" 2>/dev/null
    iptables -D INPUT -p "$d_proto" --dport "$d_port" -j ACCEPT 2>/dev/null
    iptables -D FORWARD -p "$d_proto" -d "$target_ip" --dport "$target_port" -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT 2>/dev/null
    iptables -D FORWARD -p "$d_proto" -s "$target_ip" --sport "$target_port" -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null
    
    netfilter-persistent save > /dev/null
    echo -e "${GREEN}[OK] Правило удалено.${NC}"
    read -p "Нажмите Enter..."
}

# --- ПОЛНАЯ ОЧИСТКА ---
flush_rules() {
    echo -e "\n${RED}!!! ВНИМАНИЕ !!!${NC}"
    echo "Сброс ВСЕХ настроек iptables."
    read -p "Вы уверены? (y/n): " confirm
    if [[ "$confirm" == "y" ]]; then
        iptables -P INPUT ACCEPT
        iptables -P FORWARD ACCEPT
        iptables -P OUTPUT ACCEPT
        iptables -t nat -F
        iptables -t mangle -F
        iptables -F
        iptables -X
        netfilter-persistent save > /dev/null
        echo -e "${GREEN}[OK] Очищено.${NC}"
    fi
    read -p "Нажмите Enter..."
}

# --- МЕНЮ ---
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

        echo -e "${GREEN}💰 Задонатить каналу и автору:${NC} https://pay.cloudtips.ru/p/4a618628"
        echo -e "------------------------------------------------------"
        echo ""
        echo -e "1) Настроить ${CYAN}AmneziaWG / WireGuard${NC} (UDP)"
        echo -e "2) Настроить ${CYAN}VLESS / XRay${NC} (TCP)"
        echo -e "3) Настроить ${CYAN}TProxy / MTProto${NC} (TCP)"
        echo -e "4) 🛠 Создать ${YELLOW}Кастомное правило${NC} (Разные порты, SSH, RDP...)"
        echo -e "5) Посмотреть активные правила"
        echo -e "6) ${RED}Удалить одно правило${NC}"
        echo -e "7) ${RED}Сбросить ВСЕ настройки${NC}"
        echo -e "8) ${YELLOW}Показать PROMO${NC}"
        echo -e "9) ${MAGENTA}📚 ИНСТРУКЦИЯ (Как настроить)${NC}" 
        echo -e "0) Выход"
        echo -e "------------------------------------------------------"
        read -p "Ваш выбор: " choice

        case $choice in
            1) configure_rule "udp" "AmneziaWG" ;;
            2) configure_rule "tcp" "VLESS" ;;
            3) configure_rule "tcp" "MTProto/TProxy" ;;
            4) configure_custom_rule ;;
            5) list_active_rules ;;
            6) delete_single_rule ;;
            7) flush_rules ;;
            8) show_promo ;;
            9) show_instructions ;;
            0) exit 0 ;;
            *) ;;
        esac
    done
}

# --- ЗАПУСК ---
check_root
prepare_system
show_promo
show_menu
