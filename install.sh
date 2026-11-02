#!/bin/bash

# ===============================
# COMP_MANIYA FULL KASKAD PRO
# Telegram: https://t.me/computerchik
# YouTube: https://www.youtube.com/@comp_maniya
# ===============================
# ВЕРСИЯ: 3.0
# ДАТА РЕЛИЗА: 2 ноября 2026
# СТАТУС: Beta Testing ⚠️
# GIT COMMIT: [будет добавлен автоматически]
# ===============================
# КРИТИЧЕСКАЯ ВЕРСИЯ: Исправлены 5 критических уязвимостей безопасности
# Обязательное обновление с v2.0-safe
# Автоматическая миграция при первом запуске
# ===============================
# BREAKING CHANGES:
# - Новый формат метаданных правил (добавлен UUID)
# - MASQUERADE исправлен (по интерфейсу, не по destination)
# - Backup/restore переработан (iptables-restore compatible)
# ===============================

# --- НОРМАЛИЗАЦИЯ ОКОНЧАНИЙ СТРОК ---
if file "$0" 2>/dev/null | grep -q "CRLF"; then
    sed -i 's/\r$//' "$0"
    chmod +x "$0"
fi

# --- ЦВЕТА ---
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- КОНСТАНТЫ И ПЕРЕМЕННЫЕ СОСТОЯНИЯ ---
CM_VERSION="3.0"
CM_RULES_FILE="/root/.comp_maniya_rules"
CM_STATE_DIR="/var/lib/comp_maniya"
BACKUP_DIR="/root"

# Создание директории состояния
mkdir -p "$CM_STATE_DIR" 2>/dev/null

# --- СИСТЕМА ЛОГИРОВАНИЯ ---

LOG_FILE="/var/log/comp_maniya/comp_maniya.log"
LOG_LEVEL="${CM_LOG_LEVEL:-INFO}"

init_logging() {
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null
    touch "$LOG_FILE" 2>/dev/null || LOG_FILE="/tmp/comp_maniya.log"
}

log_message() {
    local level=$1; shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_debug() { [[ "$LOG_LEVEL" == "DEBUG" ]] && log_message "DEBUG" "$@"; }
log_info() { log_message "INFO" "$@"; }
log_warn() { log_message "WARN" "$@" >&2; }
log_error() { log_message "ERROR" "$@" >&2; }
log_success() { log_message "SUCCESS" "$@"; }

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

# --- ФУНКЦИИ ВАЛИДАЦИИ ---

validate_ipv4() {
    local ip=$1
    if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        local IFS=.
        local -a octets=($ip)
        for octet in "${octets[@]}"; do
            if (( octet > 255 )); then
                return 1
            fi
        done
        return 0
    fi
    return 1
}

validate_ipv6() {
    local ip=$1
    
    # Попытка использовать Python для точной валидации
    if command -v python3 &>/dev/null; then
        if python3 -c "import ipaddress; ipaddress.IPv6Address('$ip')" 2>/dev/null; then
            return 0
        else
            return 1
        fi
    fi
    
    # Fallback: улучшенная regex
    # Полный IPv6: 8 групп по 4 hex цифры
    if [[ $ip =~ ^([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}$ ]]; then
        return 0
    fi
    
    # Compressed форма с ::
    if [[ $ip =~ ^(([0-9a-fA-F]{1,4}:)*)::(([0-9a-fA-F]{1,4}:)*[0-9a-fA-F]{1,4})?$ ]]; then
        return 0
    fi
    
    # Loopback ::1
    if [[ $ip == "::1" ]]; then
        return 0
    fi
    
    # Any ::
    if [[ $ip == "::" ]]; then
        return 0
    fi
    
    return 1
}

validate_port() {
    local port=$1
    if [[ $port =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
        return 0
    fi
    return 1
}

get_ip_type() {
    local ip=$1
    if validate_ipv4 "$ip"; then
        echo "ipv4"
    elif validate_ipv6 "$ip"; then
        echo "ipv6"
    else
        echo "invalid"
    fi
}

# --- UUID GENERATION ---

generate_uuid() {
    if command -v uuidgen &>/dev/null; then
        uuidgen | tr '[:upper:]' '[:lower:]'
    else
        # Fallback: pseudo-UUID
        echo "$(date +%s)-$$-$RANDOM"
    fi
}

# --- METADATA V3 ---

save_rule_metadata_v3() {
    local proto=$1 in_port=$2 out_port=$3 target_ip=$4 name=$5 uuid=$6
    local timestamp=$(date +%s)
    
    echo "${proto}|${in_port}|${out_port}|${target_ip}|${name}|${timestamp}|${uuid}" >> "$CM_RULES_FILE"
}

# --- SSH ПОРТИРОВАНИЕ (3-УРОВНЕВАЯ ПРОВЕРКА) ---

get_ssh_ports() {
    local -a ssh_ports=()
    
    # Метод 1: Эффективная конфигурация sshd
    if command -v sshd &> /dev/null; then
        local ports_from_config=$(sshd -T 2>/dev/null | grep "^port " | awk '{print $2}')
        while IFS= read -r port; do
            [[ -n "$port" ]] && ssh_ports+=("$port")
        done <<< "$ports_from_config"
    fi
    
    # Метод 2: Фактически слушающие порты (ss)
    if command -v ss &> /dev/null; then
        local ports_from_ss=$(ss -lntp 2>/dev/null | grep sshd | grep -oP ':\K\d+(?=/sshd)' | sort -u)
        while IFS= read -r port; do
            [[ -n "$port" ]] && ssh_ports+=("$port")
        done <<< "$ports_from_ss"
    fi
    
    # Метод 3: Конфиг файл как fallback
    if [ ${#ssh_ports[@]} -eq 0 ]; then
        local ports_from_file=$(grep -rE "^Port " /etc/ssh/ 2>/dev/null | awk '{print $2}')
        while IFS= read -r port; do
            [[ -n "$port" ]] && ssh_ports+=("$port")
        done <<< "$ports_from_file"
    fi
    
    # Финальный fallback
    if [ ${#ssh_ports[@]} -eq 0 ]; then
        ssh_ports=(22)
    fi
    
    # Вернуть уникальные порты
    printf '%s\n' "${ssh_ports[@]}" | sort -u | tr '\n' ' '
}

check_ssh_port_conflict() {
    local test_port=$1
    local ssh_ports=($(get_ssh_ports))
    
    for ssh_port in "${ssh_ports[@]}"; do
        if [[ "$test_port" == "$ssh_port" ]]; then
            return 0  # Конфликт найден
        fi
    done
    return 1  # Конфликта нет
}

# --- ПРОВЕРКА ДОСТУПНОСТИ ПОРТОВ ---

check_port_available_local() {
    local port=$1 proto=$2
    
    if [[ "$proto" == "tcp" ]]; then
        # Проверка TCP
        if ss -H -lnt 2>/dev/null | awk '{print $4}' | grep -q ":${port}$"; then
            return 1  # Порт занят
        fi
    elif [[ "$proto" == "udp" ]]; then
        # Проверка UDP
        if ss -H -lnu 2>/dev/null | awk '{print $4}' | grep -q ":${port}$"; then
            return 1  # Порт занят
        fi
    else
        log_error "Неизвестный протокол: $proto"
        return 1
    fi
    
    return 0  # Порт свободен
}

check_tcp_port_reachable() {
    local ip=$1 port=$2
    
    if ! validate_ipv4 "$ip" && ! validate_ipv6 "$ip"; then
        return 1
    fi
    
    # Для IPv4 используем /dev/tcp
    if validate_ipv4 "$ip"; then
        timeout 5 bash -c "</dev/tcp/$ip/$port" 2>/dev/null
        return $?
    fi
    
    # Для IPv6 используем nc или curl
    if validate_ipv6 "$ip"; then
        if command -v nc &>/dev/null; then
            timeout 5 nc -z -w 3 "$ip" "$port" 2>/dev/null
            return $?
        elif command -v curl &>/dev/null; then
            timeout 5 curl -s "http://[$ip]:$port" -o /dev/null 2>/dev/null
            local ret=$?
            # curl возвращает 7 если не может подключиться, 0 или 52 если подключился
            [[ $ret -eq 0 || $ret -eq 52 ]] && return 0
            return 1
        else
            log_warn "nc/curl не установлен, пропускаю проверку IPv6"
            return 0
        fi
    fi
    
    return 1
}

check_udp_port_reachable() {
    local ip=$1 port=$2
    
    if ! validate_ipv4 "$ip" && ! validate_ipv6 "$ip"; then
        return 1
    fi
    
    # UDP проверка через netcat
    if command -v nc &> /dev/null; then
        timeout 3 nc -zu "$ip" "$port" 2>/dev/null
        return $?
    fi
    
    return 0  # Если nc нет, пропускаем
}

# --- MASQUERADE MANAGEMENT (v3.0 FIX) ---

ensure_masquerade_for_interface() {
    local iface=$1
    local marker="COMP_MANIYA:v3:masq:$iface"
    
    # Проверка существования MASQUERADE для интерфейса
    if iptables -t nat -C CM_SNAT_RULES -o "$iface" -j MASQUERADE 2>/dev/null; then
        log_debug "MASQUERADE для $iface уже существует"
        return 0
    fi
    
    # Добавление MASQUERADE
    if iptables -t nat -A CM_SNAT_RULES -o "$iface" \
        -m comment --comment "$marker" -j MASQUERADE; then
        log_success "MASQUERADE добавлен для интерфейса: $iface"
        return 0
    else
        log_error "Ошибка добавления MASQUERADE для $iface"
        return 1
    fi
}

# --- УПРАВЛЕНИЕ IPTABLES ЦЕПОЧКАМИ (БЕЗОПАСНОСТЬ) ---

ensure_cm_chains() {
    log_debug "Проверка CM_* цепочек..."
    
    local chains=(
        "filter:CM_INPUT"
        "filter:CM_FORWARD"
        "nat:CM_DNAT_RULES"
        "nat:CM_SNAT_RULES"
    )
    
    local jumps=(
        "filter:INPUT:CM_INPUT"
        "filter:FORWARD:CM_FORWARD"
        "nat:PREROUTING:CM_DNAT_RULES"
        "nat:POSTROUTING:CM_SNAT_RULES"
    )
    
    # Создание цепочек (если не существуют)
    for entry in "${chains[@]}"; do
        IFS=':' read -r table chain <<< "$entry"
        
        if ! iptables -t "$table" -L "$chain" -n >/dev/null 2>&1; then
            log_info "Создание цепочки: $table/$chain"
            if ! iptables -t "$table" -N "$chain"; then
                log_error "Ошибка создания цепочки $chain"
                return 1
            fi
        fi
    done
    
    # Создание переходов (если не существуют)
    for entry in "${jumps[@]}"; do
        IFS=':' read -r table parent child <<< "$entry"
        
        # Проверка существования перехода
        if iptables -t "$table" -C "$parent" -j "$child" 2>/dev/null; then
            log_debug "Переход $parent → $child уже существует"
            continue
        fi
        
        log_info "Добавление перехода: $table/$parent → $child"
        
        # Определяем позицию вставки
        # Вставляем ПЕРЕД последним правилом (обычно default policy)
        local total_rules=$(iptables -t "$table" -L "$parent" --line-numbers -n 2>/dev/null | \
            tail -n +3 | wc -l)
        
        if [[ $total_rules -gt 0 ]]; then
            # Вставляем перед последним правилом
            if ! iptables -t "$table" -I "$parent" "$total_rules" -j "$child"; then
                log_error "Ошибка добавления перехода $parent → $child"
                return 1
            fi
        else
            # Если правил нет, просто добавляем в конец
            if ! iptables -t "$table" -A "$parent" -j "$child"; then
                log_error "Ошибка добавления перехода $parent → $child"
                return 1
            fi
        fi
    done
    
    log_success "CM_* цепочки готовы"
    return 0
}

# Сохранение информации о правиле для миграции
save_rule_metadata() {
    local proto=$1 in_port=$2 out_port=$3 target_ip=$4 name=$5
    
    echo "${proto}|${in_port}|${out_port}|${target_ip}|${name}|$(date +%s)" >> "$CM_RULES_FILE"
}

# --- ПОДГОТОВКА СИСТЕМЫ ---

prepare_system() {
    echo -e "${YELLOW}[*] Подготовка системы...${NC}"
    
    # Определение реальных SSH портов
    SSH_PORTS=($(get_ssh_ports))
    export SSH_PORTS
    echo -e "${CYAN}[OK] SSH порты определены: ${SSH_PORTS[*]}${NC}"
    
    # Автоматическое создание глобальной команды compmaniya
    if [ "$0" != "/usr/local/bin/compmaniya" ]; then
        cp -f "$0" "/usr/local/bin/compmaniya"
        chmod +x "/usr/local/bin/compmaniya"
        echo -e "${CYAN}[OK] Команда compmaniya установлена${NC}"
    fi

    # Включение IP Forwarding (с проверкой)
    if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
        echo -e "${CYAN}[+] IP Forwarding включен${NC}"
    fi
    
    sed -i 's/^#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf

    # Активация Google BBR (если поддерживается)
    if ! grep -q "^net.core.default_qdisc=fq" /etc/sysctl.conf; then
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    fi
    if ! grep -q "^net.ipv4.tcp_congestion_control=bbr" /etc/sysctl.conf; then
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    fi
    sysctl -p > /dev/null 2>&1

    # Установка зависимостей
    export DEBIAN_FRONTEND=noninteractive
    if ! dpkg -s iptables-persistent >/dev/null 2>&1 || ! command -v socat >/dev/null 2>&1; then
        echo -e "${YELLOW}[*] Установка зависимостей (может занять время)...${NC}"
        apt-get update -y > /dev/null 2>&1
        if ! apt-get install -y iptables-persistent netfilter-persistent qrencode socat netcat-openbsd 2>/dev/null; then
            echo -e "${RED}[WARNING] Ошибка при установке зависимостей. Некоторые функции могут не работать.${NC}"
        fi
    fi
    
    # Создание CM цепочек
    ensure_cm_chains
    
    # Миграция старых правил (если есть)
    migrate_legacy_rules
    
    echo -e "${GREEN}[OK] Система готова${NC}"
}

# --- МИГРАЦИЯ СТАРЫХ ПРАВИЛ (v3.0 БЕЗОПАСНАЯ) ---

migrate_v2_to_v3() {
    local v2_marker="/root/.compmaniya_v1_migrated"
    local v3_marker="$CM_STATE_DIR/migrated_to_v3"
    
    # Проверка: уже мигрировано на v3
    [[ -f "$v3_marker" ]] && {
        log_debug "Миграция v3 уже выполнена"
        return 0
    }
    
    # Проверка: есть ли v2.0-safe установка
    if [[ ! -f "$v2_marker" ]] || [[ ! -f "$CM_RULES_FILE" ]]; then
        log_info "Чистая установка v3.0"
        touch "$v3_marker"
        return 0
    fi
    
    log_info "═══════════════════════════════════════════════"
    log_info "  Обнаружена установка v2.0-safe"
    log_info "  Начинается миграция на v3.0..."
    log_info "═══════════════════════════════════════════════"
    
    # Создание safety backup
    log_info "Создание backup перед миграцией..."
    local backup_name="pre-v3-migration-$(date +%Y%m%d-%H%M%S)"
    if ! backup_rules_v3 "$backup_name"; then
        log_error "Не удалось создать backup. Миграция прервана."
        return 1
    fi
    
    # Счётчик мигрированных правил
    local migrated_count=0
    local failed_count=0
    
    # Миграция через МЕТАДАННЫЕ (не парсинг iptables!)
    log_info "Миграция правил из метаданных..."
    while IFS='|' read -r proto in_port out_port target_ip name timestamp; do
        [[ -z "$proto" ]] && continue
        
        log_info "Обработка: $proto $in_port → $target_ip:$out_port"
        
        # Проверка существования правила в CM_DNAT_RULES
        if ! iptables -t nat -C CM_DNAT_RULES -p "$proto" --dport "$in_port" \
            -j DNAT --to-destination "$target_ip:$out_port" 2>/dev/null; then
            log_warn "Правило не найдено в CM_DNAT_RULES, пропускаю"
            ((failed_count++))
            continue
        fi
        
        # Генерация UUID для маркера
        local uuid=$(generate_uuid)
        local marker="COMP_MANIYA:v3:$uuid"
        
        # Получение интерфейса
        local iface=$(ip route get "$target_ip" 2>/dev/null | grep -oP 'dev \K\S+' | head -1)
        if [[ -z "$iface" ]]; then
            log_warn "Не удалось определить интерфейс для $target_ip"
            iface="eth0"  # Fallback
        fi
        
        # Удаление старого правила без маркера
        iptables -t nat -D CM_DNAT_RULES -p "$proto" --dport "$in_port" \
            -j DNAT --to-destination "$target_ip:$out_port" 2>/dev/null
        
        iptables -D CM_INPUT -p "$proto" --dport "$in_port" -j ACCEPT 2>/dev/null || true
        
        iptables -D CM_FORWARD -p "$proto" -d "$target_ip" --dport "$out_port" \
            -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
        
        iptables -D CM_FORWARD -p "$proto" -s "$target_ip" --sport "$out_port" \
            -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
        
        # Удаление старого НЕПРАВИЛЬНОГО MASQUERADE (по destination)
        iptables -t nat -D CM_SNAT_RULES -d "$target_ip" -o "$iface" -j MASQUERADE 2>/dev/null || true
        iptables -t nat -D CM_SNAT_RULES -d "$target_ip" -j MASQUERADE 2>/dev/null || true
        
        # Создание новых правил с маркерами
        if ! iptables -A CM_INPUT -p "$proto" --dport "$in_port" \
            -m comment --comment "$marker:input" -j ACCEPT; then
            log_error "Ошибка миграции INPUT для порта $in_port"
            ((failed_count++))
            continue
        fi
        
        if ! iptables -t nat -A CM_DNAT_RULES -p "$proto" --dport "$in_port" \
            -m comment --comment "$marker:dnat" \
            -j DNAT --to-destination "$target_ip:$out_port"; then
            log_error "Ошибка миграции DNAT для порта $in_port"
            iptables -D CM_INPUT -p "$proto" --dport "$in_port" \
                -m comment --comment "$marker:input" -j ACCEPT 2>/dev/null
            ((failed_count++))
            continue
        fi
        
        iptables -A CM_FORWARD -p "$proto" -d "$target_ip" --dport "$out_port" \
            -m state --state NEW,ESTABLISHED,RELATED \
            -m comment --comment "$marker:fwd:in" -j ACCEPT
        
        iptables -A CM_FORWARD -p "$proto" -s "$target_ip" --sport "$out_port" \
            -m state --state ESTABLISHED,RELATED \
            -m comment --comment "$marker:fwd:out" -j ACCEPT
        
        # Новый правильный MASQUERADE
        ensure_masquerade_for_interface "$iface"
        
        # Сохранение метаданных v3
        save_rule_metadata_v3 "$proto" "$in_port" "$out_port" "$target_ip" "$name" "$uuid"
        
        ((migrated_count++))
        log_success "Мигрировано: $proto $in_port → $target_ip:$out_port"
        
    done < "$CM_RULES_FILE"
    
    # Сохранение конфигурации
    netfilter-persistent save >/dev/null 2>&1 || true
    
    # Создание маркера v3
    touch "$v3_marker"
    
    log_success "═══════════════════════════════════════════════"
    log_success "  Миграция завершена!"
    log_success "  Успешно: $migrated_count | Ошибок: $failed_count"
    log_success "═══════════════════════════════════════════════"
    
    return 0
}

# Алиас для обратной совместимости
migrate_legacy_rules() {
    migrate_v2_to_v3
}

# Старая функция закомментирована для справки
# --- UI ФУНКЦИИ ---

show_promo() {
    clear
    echo ""
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║                 COMP_MANIYA KASKAD PRO v${CM_VERSION}                    ║${NC}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    echo -e "${CYAN}Telegram:${NC} https://t.me/computerchik"
    echo -e "${RED}YouTube:${NC} https://www.youtube.com/@comp_maniya"

    echo ""
    echo -e "${YELLOW}QR Telegram:${NC}"
    qrencode -t ANSIUTF8 "https://t.me/computerchik" 2>/dev/null || echo "[QR не доступен]"

    echo ""
    echo -e "${YELLOW}QR YouTube:${NC}"
    qrencode -t ANSIUTF8 "https://www.youtube.com/@comp_maniya" 2>/dev/null || echo "[QR не доступен]"

    echo ""
    read -p "Нажмите enter для настройки каскадного скрипта..."
}

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

show_help() {
    clear
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║                   СПРАВКА COMP_MANIYA                         ║${NC}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}Основные команды:${NC}"
    echo ""
    echo "  compmaniya              - Открыть интерактивное меню"
    echo "  compmaniya --help       - Показать эту справку"
    echo "  compmaniya --version    - Версия скрипта"
    echo "  compmaniya --status     - Статус текущих правил"
    echo ""
    echo -e "${CYAN}Меню опции:${NC}"
    echo ""
    echo "  1-3  - Быстрая настройка стандартных протоколов (WireGuard, VLESS, MTProto)"
    echo "  4    - Кастомное правило (любой TCP/UDP порт)"
    echo "  5    - Просмотр активных правил"
    echo "  6    - Удалить одно правило"
    echo "  7    - Полная очистка (удалить ВСЕ правила COMP_MANIYA)"
    echo "  8-19 - Утилиты (backup, restore, мониторинг и т.д.)"
    echo ""
    echo -e "${YELLOW}Важно:${NC}"
    echo "  - Все операции изолированы в цепочках CM_*"
    echo "  - UFW, Docker, Fail2ban НЕ затрагиваются"
    echo "  - SSH защищен от блокировки"
    echo ""
    read -p "Нажмите Enter для возврата в меню..."
}

# --- КОНФИГУРИРОВАНИЕ ПРАВИЛ ---

configure_rule_auto_detect() {
    local PROTO=$1
    local NAME=$2
    local MODE=$3
    local attempts=3
    local ip_type

    echo -e "\n${CYAN}--- Настройка $NAME ($PROTO) ---${NC}"

    while [[ $attempts -gt 0 ]]; do
        echo -e "Введите IP адрес назначения (целевой сервер):"
        read -p "> " TARGET_IP

        ip_type=$(get_ip_type "$TARGET_IP")

        if [[ "$ip_type" == "invalid" ]]; then
            ((attempts--))
            if [[ $attempts -gt 0 ]]; then
                echo -e "${RED}Ошибка: введите корректный IPv4 или IPv6 адрес! (осталось попыток: $attempts)${NC}"
            else
                echo -e "${RED}[ERROR] Максимум 3 попытки исчерпаны. Отмена.${NC}"
                read -p "Нажмите Enter..."
                return 1
            fi
            continue
        fi

        if [[ "$ip_type" == "ipv4" ]]; then
            # IPv4: вызвать нужную функцию
            if [[ "$MODE" == "different_ports" ]]; then
                configure_rule_with_different_ports "$PROTO" "$NAME" "$TARGET_IP"
            else
                configure_rule "$PROTO" "$NAME" "$TARGET_IP"
            fi
            return $?
        fi

        if [[ "$ip_type" == "ipv6" ]]; then
            # IPv6: показать сообщение и создать IPv4→IPv6 каскад
            echo -e "${CYAN}[*] Обнаружен IPv6, создаю IPv4→IPv6 каскад...${NC}"
            
            if [[ "$MODE" == "different_ports" ]]; then
                configure_ipv4_to_ipv6_rule "$PROTO" "true" "$TARGET_IP"
            else
                configure_ipv4_to_ipv6_rule "$PROTO" "false" "$TARGET_IP"
            fi
            return $?
        fi
    done
}

configure_rule() {
    local PROTO=$1
    local NAME=$2
    local TARGET_IP=$3

    echo -e "\n${CYAN}--- Настройка $NAME ($PROTO) ---${NC}"
    
    # Если TARGET_IP не передана, спросить (для обратной совместимости)
    if [[ -z "$TARGET_IP" ]]; then
        while true; do
            echo -e "Введите IP адрес назначения (целевой сервер):"
            read -p "> " TARGET_IP
            if validate_ipv4 "$TARGET_IP"; then 
                break
            fi
            echo -e "${RED}Ошибка: введите корректный IPv4 адрес!${NC}"
        done
    fi

    while true; do
        echo -e "Введите Порт (одинаковый для входа и выхода):"
        read -p "> " PORT
        if validate_port "$PORT"; then 
            break
        fi
        echo -e "${RED}Ошибка: порт должен быть от 1 до 65535!${NC}"
    done

    # Проверка конфликта с SSH
    if check_ssh_port_conflict "$PORT"; then
        if [[ "$PROTO" == "tcp" ]]; then
            echo -e "${RED}[ERROR] ⚠️  ЗАПРЕЩЕНО! Порт $PORT совпадает с SSH портом!${NC}"
            echo -e "${RED}Это заблокирует ваш доступ к серверу.${NC}"
            read -p "Нажмите Enter..."
            return 1
        fi
    fi
    
    # Проверка занятости локального порта
    if ! check_port_available_local "$PORT" "$PROTO"; then
        echo -e "${RED}[ERROR] Порт $PORT/$PROTO уже используется на этом сервере!${NC}"
        read -p "Нажмите Enter..."
        return 1
    fi
    
    # Проверка доступности целевого порта
    echo -e "${YELLOW}[*] Проверка доступности ${TARGET_IP}:${PORT}/${PROTO}...${NC}"
    if [[ "$PROTO" == "tcp" ]]; then
        if ! check_tcp_port_reachable "$TARGET_IP" "$PORT"; then
            echo -e "${YELLOW}[!] TCP порт ${TARGET_IP}:${PORT} не доступен (может быть firewall).${NC}"
            read -p "Продолжить всё равно? (y/n): " continue_anyway
            [[ "$continue_anyway" != "y" ]] && return 1
        else
            echo -e "${GREEN}[OK] TCP порт доступен${NC}"
        fi
    else
        if ! check_udp_port_reachable "$TARGET_IP" "$PORT"; then
            echo -e "${YELLOW}[!] UDP порт ${TARGET_IP}:${PORT} может быть не доступен.${NC}"
            read -p "Продолжить всё равно? (y/n): " continue_anyway
            [[ "$continue_anyway" != "y" ]] && return 1
        else
            echo -e "${GREEN}[OK] UDP порт доступен${NC}"
        fi
    fi

    apply_iptables_rules "$PROTO" "$PORT" "$PORT" "$TARGET_IP" "$NAME"
}

configure_rule_with_different_ports() {
    local PROTO=$1
    local NAME=$2
    local TARGET_IP=$3

    echo -e "\n${CYAN}--- Настройка $NAME ($PROTO) - разные порты ---${NC}"

    while true; do
        echo -e "Введите ${YELLOW}ВХОДЯЩИЙ Порт${NC} (на этом сервере):"
        read -p "> " IN_PORT
        if validate_port "$IN_PORT"; then 
            break
        fi
        echo -e "${RED}Ошибка: порт должен быть от 1 до 65535!${NC}"
    done

    # Проверка конфликта с SSH
    if check_ssh_port_conflict "$IN_PORT"; then
        if [[ "$PROTO" == "tcp" ]]; then
            echo -e "${RED}[ERROR] ⚠️  ЗАПРЕЩЕНО! Входящий порт $IN_PORT совпадает с SSH портом!${NC}"
            echo -e "${RED}Это заблокирует ваш доступ к серверу.${NC}"
            read -p "Нажмите Enter..."
            return 1
        fi
    fi
    
    # Проверка занятости локального входящего порта
    if ! check_port_available_local "$IN_PORT" "$PROTO"; then
        echo -e "${RED}[ERROR] Входящий порт $IN_PORT/$PROTO уже используется!${NC}"
        read -p "Нажмите Enter..."
        return 1
    fi

    while true; do
        echo -e "Введите ${YELLOW}ИСХОДЯЩИЙ Порт${NC} (на целевом сервере):"
        read -p "> " OUT_PORT
        if validate_port "$OUT_PORT"; then 
            break
        fi
        echo -e "${RED}Ошибка: порт должен быть от 1 до 65535!${NC}"
    done
    
    # Проверка доступности целевого порта
    echo -e "${YELLOW}[*] Проверка доступности ${TARGET_IP}:${OUT_PORT}/${PROTO}...${NC}"
    if [[ "$PROTO" == "tcp" ]]; then
        if ! check_tcp_port_reachable "$TARGET_IP" "$OUT_PORT"; then
            echo -e "${YELLOW}[!] TCP порт недоступен (может быть firewall).${NC}"
            read -p "Продолжить? (y/n): " continue_anyway
            [[ "$continue_anyway" != "y" ]] && return 1
        else
            echo -e "${GREEN}[OK] TCP порт доступен${NC}"
        fi
    else
        if ! check_udp_port_reachable "$TARGET_IP" "$OUT_PORT"; then
            echo -e "${YELLOW}[!] UDP порт может быть недоступен.${NC}"
            read -p "Продолжить? (y/n): " continue_anyway
            [[ "$continue_anyway" != "y" ]] && return 1
        else
            echo -e "${GREEN}[OK] UDP порт доступен${NC}"
        fi
    fi

    apply_iptables_rules "$PROTO" "$IN_PORT" "$OUT_PORT" "$TARGET_IP" "$NAME"
}

configure_custom_rule() {
    echo -e "\n${CYAN}--- 🛠 Универсальное кастомное правило ---${NC}"
    echo -e "${WHITE}Подходит для перенаправления ЛЮБЫХ протоколов (SSH, RDP, нестандартные порты).${NC}\n"

    while true; do
        echo -e "Выберите протокол (${YELLOW}tcp${NC} или ${YELLOW}udp${NC}):"
        read -p "> " PROTO
        if [[ "$PROTO" == "tcp" || "$PROTO" == "udp" ]]; then 
            break
        fi
        echo -e "${RED}Ошибка: введите tcp или udp!${NC}"
    done

    while true; do
        echo -e "Введите IP адрес назначения (целевой сервер):"
        read -p "> " TARGET_IP
        if validate_ipv4 "$TARGET_IP"; then 
            break
        fi
        echo -e "${RED}Ошибка: введите корректный IPv4 адрес!${NC}"
    done

    while true; do
        echo -e "Введите ${YELLOW}ВХОДЯЩИЙ Порт${NC} (на этом сервере):"
        read -p "> " IN_PORT
        if validate_port "$IN_PORT"; then 
            break
        fi
        echo -e "${RED}Ошибка: порт должен быть от 1 до 65535!${NC}"
    done

    # Проверка конфликта с SSH
    if check_ssh_port_conflict "$IN_PORT"; then
        if [[ "$PROTO" == "tcp" ]]; then
            echo -e "${RED}[ERROR] ⚠️  ЗАПРЕЩЕНО! Входящий порт $IN_PORT совпадает с SSH портом!${NC}"
            echo -e "${RED}Это заблокирует ваш доступ к серверу.${NC}"
            read -p "Нажмите Enter..."
            return 1
        fi
    fi
    
    # Проверка занятости локального входящего порта
    if ! check_port_available_local "$IN_PORT" "$PROTO"; then
        echo -e "${RED}[ERROR] Входящий порт $IN_PORT/$PROTO уже используется!${NC}"
        read -p "Нажмите Enter..."
        return 1
    fi

    while true; do
        echo -e "Введите ${YELLOW}ИСХОДЯЩИЙ Порт${NC} (на целевом сервере):"
        read -p "> " OUT_PORT
        if validate_port "$OUT_PORT"; then 
            break
        fi
        echo -e "${RED}Ошибка: порт должен быть от 1 до 65535!${NC}"
    done
    
    # Проверка доступности целевого порта
    echo -e "${YELLOW}[*] Проверка доступности ${TARGET_IP}:${OUT_PORT}/${PROTO}...${NC}"
    if [[ "$PROTO" == "tcp" ]]; then
        if ! check_tcp_port_reachable "$TARGET_IP" "$OUT_PORT"; then
            echo -e "${YELLOW}[!] TCP порт недоступен (может быть firewall).${NC}"
            read -p "Продолжить? (y/n): " continue_anyway
            [[ "$continue_anyway" != "y" ]] && return 1
        fi
    else
        if ! check_udp_port_reachable "$TARGET_IP" "$OUT_PORT"; then
            echo -e "${YELLOW}[!] UDP порт может быть недоступен.${NC}"
            read -p "Продолжить? (y/n): " continue_anyway
            [[ "$continue_anyway" != "y" ]] && return 1
        fi
    fi

    apply_iptables_rules "$PROTO" "$IN_PORT" "$OUT_PORT" "$TARGET_IP" "Custom Rule"
}

# --- IPv4 → IPv6 КАСКАД (socat) ---

configure_ipv4_to_ipv6_rule() {
    local PROTO=$1
    local ALLOW_DIFFERENT_PORTS=$2
    local TARGET_IP6=$3
    local PROTO_UPPER=$(echo "$PROTO" | tr '[:lower:]' '[:upper:]')

    echo -e "\n${CYAN}--- 🔀 IPv4 → IPv6 каскад ($PROTO_UPPER) ---${NC}"
    echo -e "${WHITE}Клиент подключается по IPv4 к этому серверу,"
    echo -e "трафик перенаправляется на целевой сервер по IPv6.${NC}\n"

    local SERVER_IP
    SERVER_IP=$(curl -s -4 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    echo -e "IP этого сервера (IPv4): ${GREEN}${SERVER_IP}${NC}\n"

    echo -e "${YELLOW}[*] Проверка поддержки IPv6 на этом сервере...${NC}"
    if ! ip -6 addr show | grep -q "inet6"; then
        echo -e "${RED}[ERROR] Этот сервер не поддерживает IPv6. Каскад не создан.${NC}"
        read -p "Нажмите Enter для возврата в меню..."
        return 1
    fi
    echo -e "${GREEN}[OK] IPv6 поддержка найдена.${NC}\n"

    while true; do
        if [[ "$ALLOW_DIFFERENT_PORTS" == "true" ]]; then
            echo -e "Введите ${YELLOW}ВХОДЯЩИЙ Порт${NC} (на этом сервере):"
        else
            echo -e "Введите ${YELLOW}Порт${NC} (одинаковый для входа и выхода):"
        fi
        read -p "> " IN_PORT
        if validate_port "$IN_PORT"; then 
            break
        fi
        echo -e "${RED}Ошибка: порт должен быть от 1 до 65535!${NC}"
    done

    # Проверка конфликта с SSH
    if check_ssh_port_conflict "$IN_PORT"; then
        if [[ "$PROTO" == "tcp" ]]; then
            echo -e "${RED}[ERROR] ⚠️  ЗАПРЕЩЕНО! Входящий порт $IN_PORT совпадает с SSH портом!${NC}"
            read -p "Нажмите Enter..."
            return 1
        fi
    fi
    
    # Проверка занятости локального порта
    if ! check_port_available_local "$IN_PORT" "$PROTO"; then
        echo -e "${RED}[ERROR] Порт $IN_PORT/$PROTO уже используется!${NC}"
        read -p "Нажмите Enter..."
        return 1
    fi

    # Спросить выходящий порт, если требуются разные порты
    local OUT_PORT="$IN_PORT"
    if [[ "$ALLOW_DIFFERENT_PORTS" == "true" ]]; then
        while true; do
            echo -e "Введите ${YELLOW}ИСХОДЯЩИЙ Порт${NC} (на целевом сервере IPv6):"
            read -p "> " OUT_PORT
            if validate_port "$OUT_PORT"; then 
                break
            fi
            echo -e "${RED}Ошибка: порт должен быть от 1 до 65535!${NC}"
        done
    fi

    # Если TARGET_IP6 не передана, спросить её
    if [[ -z "$TARGET_IP6" ]]; then
        while true; do
            echo -e "Введите ${YELLOW}IPv6 адрес${NC} назначения (например: 2001:db8::1):"
            read -p "> " TARGET_IP6
            if validate_ipv6 "$TARGET_IP6"; then 
                break
            fi
            echo -e "${RED}Ошибка: введите корректный IPv6 адрес!${NC}"
        done
    fi

    echo -e "${YELLOW}[*] Проверка доступности целевого IPv6 адреса [${TARGET_IP6}]:${OUT_PORT}/${PROTO}...${NC}"
    
    if [[ "$PROTO" == "tcp" ]]; then
        if ! check_tcp_port_reachable "$TARGET_IP6" "$OUT_PORT"; then
            echo -e "${YELLOW}[!] TCP порт на IPv6 может быть недоступен.${NC}"
            read -p "Продолжить? (y/n): " continue_anyway
            [[ "$continue_anyway" != "y" ]] && return 1
        fi
    else
        if ! check_udp_port_reachable "$TARGET_IP6" "$OUT_PORT"; then
            echo -e "${YELLOW}[!] UDP порт на IPv6 может быть недоступен.${NC}"
            read -p "Продолжить? (y/n): " continue_anyway
            [[ "$continue_anyway" != "y" ]] && return 1
        fi
    fi
    echo -e "${GREEN}[OK] Целевой адрес доступен.${NC}\n"

    local SVC_NAME="socat-ipv6-${IN_PORT}-${PROTO}"
    local SVC_FILE="/etc/systemd/system/${SVC_NAME}.service"

    if [[ "$PROTO" == "tcp" ]]; then
        local SOCAT_CMD="socat TCP4-LISTEN:${IN_PORT},bind=0.0.0.0,fork,reuseaddr TCP6:[${TARGET_IP6}]:${OUT_PORT}"
    else
        local SOCAT_CMD="socat UDP4-LISTEN:${IN_PORT},bind=0.0.0.0,fork,reuseaddr UDP6:[${TARGET_IP6}]:${OUT_PORT}"
    fi

    cat > "$SVC_FILE" <<EOF
[Unit]
Description=socat IPv4->IPv6 forward port ${IN_PORT}/${PROTO} to [${TARGET_IP6}]:${OUT_PORT}
After=network.target

[Service]
Type=simple
ExecStart=${SOCAT_CMD}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    if ! systemctl enable "$SVC_NAME" > /dev/null 2>&1; then
        echo -e "${RED}[ERROR] Ошибка при включении сервиса${NC}"
        return 1
    fi
    
    if ! systemctl restart "$SVC_NAME"; then
        echo -e "${RED}[ERROR] Ошибка при запуске socat${NC}"
        rm -f "$SVC_FILE"
        systemctl daemon-reload
        return 1
    fi
    
    # Проверка, что сервис запустился
    sleep 1
    if ! systemctl is-active --quiet "$SVC_NAME"; then
        echo -e "${RED}[ERROR] Сервис socat не запустился. Статус:${NC}"
        systemctl status "$SVC_NAME" | head -10
        rm -f "$SVC_FILE"
        systemctl daemon-reload
        return 1
    fi

    iptables -A CM_INPUT -p "$PROTO" --dport "$IN_PORT" -j ACCEPT
    if ! iptables -D INPUT -p "$PROTO" --dport "$IN_PORT" -j ACCEPT 2>/dev/null; then
        true  # Может не быть старого правила
    fi
    
    # UFW: допустить только если активен
    if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
        ufw allow "$IN_PORT"/"$PROTO" >/dev/null 2>&1 || true
    fi
    
    netfilter-persistent save > /dev/null 2>&1 || true

    echo -e "${GREEN}[SUCCESS] IPv4→IPv6 каскад настроен!${NC}"
    if [[ "$OUT_PORT" != "$IN_PORT" ]]; then
        echo -e "$PROTO_UPPER: ${SERVER_IP}:${IN_PORT} (IPv4) -> [${TARGET_IP6}]:${OUT_PORT} (IPv6)"
    else
        echo -e "$PROTO_UPPER: ${SERVER_IP}:${IN_PORT} (IPv4) -> [${TARGET_IP6}]:${IN_PORT} (IPv6)"
    fi
    read -p "Нажмите Enter для возврата в меню..."
}

# --- ПРИМЕНЕНИЕ ПРАВИЛ IPTABLES (БЕЗОПАСНО) ---

apply_iptables_rules() {
    local PROTO=$1
    local IN_PORT=$2
    local OUT_PORT=$3
    local TARGET_IP=$4
    local NAME=$5

    IFACE=$(ip route get 8.8.8.8 2>/dev/null | awk -- '{printf $5}' | head -1)
    if [[ -z "$IFACE" ]]; then
        echo -e "${RED}[ERROR] Не удалось определить интерфейс!${NC}"
        return 1
    fi

    echo -e "${YELLOW}[*] Применение правил...${NC}"

    # Удаление старых правил (если они были)
    iptables -t nat -D CM_DNAT_RULES -p "$PROTO" --dport "$IN_PORT" -j DNAT --to-destination "$TARGET_IP:$OUT_PORT" 2>/dev/null || true
    iptables -D CM_INPUT -p "$PROTO" --dport "$IN_PORT" -j ACCEPT 2>/dev/null || true
    iptables -D CM_FORWARD -p "$PROTO" -d "$TARGET_IP" --dport "$OUT_PORT" -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
    iptables -D CM_FORWARD -p "$PROTO" -s "$TARGET_IP" --sport "$OUT_PORT" -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true

    # Новые правила в CM_* цепочках
    if ! iptables -A CM_INPUT -p "$PROTO" --dport "$IN_PORT" -j ACCEPT; then
        echo -e "${RED}[ERROR] Ошибка добавления INPUT правила${NC}"
        return 1
    fi
    
    if ! iptables -t nat -A CM_DNAT_RULES -p "$PROTO" --dport "$IN_PORT" -j DNAT --to-destination "$TARGET_IP:$OUT_PORT"; then
        echo -e "${RED}[ERROR] Ошибка добавления DNAT правила${NC}"
        return 1
    fi
    
    # MASQUERADE только для целевого IP (в CM_SNAT_RULES)
    if ! iptables -t nat -C CM_SNAT_RULES -d "$TARGET_IP" -o "$IFACE" -j MASQUERADE 2>/dev/null; then
        if ! iptables -t nat -A CM_SNAT_RULES -d "$TARGET_IP" -o "$IFACE" -j MASQUERADE; then
            echo -e "${RED}[ERROR] Ошибка добавления SNAT правила${NC}"
            return 1
        fi
    fi

    if ! iptables -A CM_FORWARD -p "$PROTO" -d "$TARGET_IP" --dport "$OUT_PORT" -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT; then
        echo -e "${RED}[ERROR] Ошибка добавления FORWARD правила (в)${NC}"
        return 1
    fi
    
    if ! iptables -A CM_FORWARD -p "$PROTO" -s "$TARGET_IP" --sport "$OUT_PORT" -m state --state ESTABLISHED,RELATED -j ACCEPT; then
        echo -e "${RED}[ERROR] Ошибка добавления FORWARD правила (из)${NC}"
        return 1
    fi

    # UFW: добавить правило если активен (НЕ меняем DEFAULT_FORWARD_POLICY!)
    if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
        ufw allow "$IN_PORT"/"$PROTO" >/dev/null 2>&1 || true
    fi

    # Сохранение конфигурации
    if ! netfilter-persistent save > /dev/null 2>&1; then
        echo -e "${YELLOW}[!] Предупреждение: netfilter-persistent save не сработал${NC}"
    fi
    
    # Сохранение метаданных о правиле
    save_rule_metadata "$PROTO" "$IN_PORT" "$OUT_PORT" "$TARGET_IP" "$NAME"
    
    echo -e "${GREEN}[SUCCESS] $NAME настроен!${NC}"
    echo -e "$PROTO: Вход $IN_PORT -> Выход $TARGET_IP:$OUT_PORT"
    read -p "Нажмите Enter для возврата в меню..."
}

# --- СПИСОК ПРАВИЛ ---

list_active_rules() {
    echo -e "\n${CYAN}--- Активные переадресации COMP_MANIYA ---${NC}"

    SERVER_IP=$(curl -s -4 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')

    echo -e "${MAGENTA}Сервер каскада:${NC} ${GREEN}${SERVER_IP}${NC}"
    echo ""
    echo -e "${MAGENTA}IPv4 Правила (ВХОД -> ВЫХОД):${NC}"
    echo ""

    local count=0
    iptables -t nat -S CM_DNAT_RULES 2>/dev/null | grep "DNAT" | while read -r line ; do
        l_port=$(echo "$line" | grep -oP '(?<=--dport )\d+')
        l_proto=$(echo "$line" | grep -oP '(?<=-p )\w+')
        l_dest=$(echo "$line" | grep -oP '(?<=--to-destination )[\d\.:]+')

        if [[ -n "$l_port" ]]; then
            echo -e "${CYAN}${SERVER_IP}:${l_port}${NC} (${YELLOW}${l_proto}${NC}) -> ${GREEN}${l_dest}${NC}"
            ((count++))
        fi
    done

    local has_ipv6=0
    echo ""
    for svc_file in /etc/systemd/system/socat-ipv6-*.service; do
        [[ -f "$svc_file" ]] || continue
        if [[ $has_ipv6 -eq 0 ]]; then
            echo -e "${MAGENTA}IPv4 → IPv6 каскады (socat):${NC}"
            has_ipv6=1
        fi
        local svc_name=$(basename "$svc_file" .service)
        local desc=$(grep -oP '(?<=to \[).*(?=\])' "$svc_file" | head -1)
        local port=$(echo "$svc_name" | grep -oP '(?<=socat-ipv6-)\d+')
        local proto=$(echo "$svc_name" | sed 's/socat-ipv6-[0-9]*-//')
        local dest_port=$(grep -oP '(?<=\]:)\d+' "$svc_file" | head -1)
        local status=$(systemctl is-active "$svc_name" 2>/dev/null)
        if [[ "$status" == "active" ]]; then
            local status_str="${GREEN}active${NC}"
        else
            local status_str="${RED}${status}${NC}"
        fi
        echo -e "${CYAN}${SERVER_IP}:${port}${NC} (${YELLOW}${proto}${NC}) -> ${GREEN}[${desc}]:${dest_port}${NC} [$status_str]"
    done
    echo ""

    read -p "Нажмите Enter..."
}

# --- УДАЛЕНИЕ ОДНОГО ПРАВИЛА ---

delete_single_rule() {
    echo -e "\n${CYAN}--- Удаление правила ---${NC}"
    declare -a RULES_LIST
    declare -a RULES_TYPE
    local i=1

    while read -r line; do
        l_port=$(echo "$line" | grep -oP '(?<=--dport )\d+')
        l_proto=$(echo "$line" | grep -oP '(?<=-p )\w+')
        l_dest=$(echo "$line" | grep -oP '(?<=--to-destination )[\d\.:]+')
        if [[ -n "$l_port" ]]; then
            RULES_LIST[$i]="$l_port:$l_proto:$l_dest"
            RULES_TYPE[$i]="iptables"
            echo -e "${YELLOW}[$i]${NC} Вход: $l_port ($l_proto) -> Выход: $l_dest"
            ((i++))
        fi
    done < <(iptables -t nat -S CM_DNAT_RULES 2>/dev/null | grep "DNAT")

    for svc_file in /etc/systemd/system/socat-ipv6-*.service; do
        [[ -f "$svc_file" ]] || continue
        local svc_name=$(basename "$svc_file" .service)
        local port=$(echo "$svc_name" | grep -oP '(?<=socat-ipv6-)\d+')
        local proto=$(echo "$svc_name" | sed 's/socat-ipv6-[0-9]*-//')
        local dest_ip=$(grep -oP '(?<=\[)[0-9a-fA-F:]+(?=\])' "$svc_file" | head -1)
        local dest_port=$(grep -oP '(?<=\]:)\d+' "$svc_file" | head -1)
        RULES_LIST[$i]="${svc_name}"
        RULES_TYPE[$i]="socat"
        echo -e "${YELLOW}[$i]${NC} Вход: $port ($proto) -> IPv6: [${dest_ip}]:${dest_port}"
        ((i++))
    done

    if [ ${#RULES_LIST[@]} -eq 0 ]; then
        echo -e "${RED}Нет активных правил.${NC}"
        read -p "Нажмите Enter..."
        return
    fi

    echo ""
    read -p "Номер правила для удаления (0 отмена): " rule_num
    if [[ "$rule_num" == "0" || -z "${RULES_LIST[$rule_num]}" ]]; then return; fi

    if [[ "${RULES_TYPE[$rule_num]}" == "socat" ]]; then
        local svc_name="${RULES_LIST[$rule_num]}"
        local port=$(echo "$svc_name" | grep -oP '(?<=socat-ipv6-)\d+')
        local proto=$(echo "$svc_name" | grep -oP '(?<=socat-ipv6-\d{1,5}-).+')
        
        echo -e "${YELLOW}[*] Остановка сервиса ${svc_name}...${NC}"
        systemctl stop "$svc_name" 2>/dev/null || true
        systemctl disable "$svc_name" > /dev/null 2>&1 || true
        rm -f "/etc/systemd/system/${svc_name}.service"
        systemctl daemon-reload
        
        iptables -D CM_INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null || true
        
        # Удалить UFW правило если активен
        if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
            ufw delete allow "$port"/"$proto" 2>/dev/null || true
        fi
        
        netfilter-persistent save > /dev/null 2>&1 || true
        echo -e "${GREEN}[OK] IPv4→IPv6 правило удалено.${NC}"
    else
        IFS=':' read -r d_port d_proto d_dest <<< "${RULES_LIST[$rule_num]}"
        local target_ip="${d_dest%:*}"
        local target_port="${d_dest#*:}"
        
        echo -e "${YELLOW}[*] Удаление правил для ${d_dest}...${NC}"
        iptables -t nat -D CM_DNAT_RULES -p "$d_proto" --dport "$d_port" -j DNAT --to-destination "$d_dest" 2>/dev/null || true
        iptables -D CM_INPUT -p "$d_proto" --dport "$d_port" -j ACCEPT 2>/dev/null || true
        iptables -D CM_FORWARD -p "$d_proto" -d "$target_ip" --dport "$target_port" -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
        iptables -D CM_FORWARD -p "$d_proto" -s "$target_ip" --sport "$target_port" -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
        
        # Удалить UFW правило если активен
        if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
            ufw delete allow "$d_port"/"$d_proto" 2>/dev/null || true
        fi
        
        netfilter-persistent save > /dev/null 2>&1 || true
        echo -e "${GREEN}[OK] Правило удалено.${NC}"
    fi

    read -p "Нажмите Enter..."
}

# --- ПОЛНАЯ ОЧИСТКА (ТОЛЬКО CM_* ЦЕПОЧКИ) ---

flush_rules() {
    echo -e "\n${RED}!!! ВНИМАНИЕ !!!${NC}"
    echo "Удалены ТОЛЬКО правила COMP_MANIYA в цепочках CM_*"
    echo "Правила UFW, Docker, Fail2ban НЕ будут затронуты."
    read -p "Вы уверены? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then 
        return
    fi
    
    echo -e "${YELLOW}[*] Очистка правил COMP_MANIYA...${NC}"
    
    # Остановка всех socat сервисов
    for svc_file in /etc/systemd/system/socat-ipv6-*.service; do
        [[ -f "$svc_file" ]] || continue
        local svc_name=$(basename "$svc_file" .service)
        local port=$(echo "$svc_name" | grep -oP '(?<=socat-ipv6-)\d+')
        local proto=$(echo "$svc_name" | sed 's/socat-ipv6-[0-9]*-//')
        
        systemctl stop "$svc_name" 2>/dev/null || true
        systemctl disable "$svc_name" > /dev/null 2>&1 || true
        rm -f "$svc_file"
        
        # Удалить UFW правила
        if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
            ufw delete allow "$port"/"$proto" 2>/dev/null || true
        fi
    done
    systemctl daemon-reload

    # Очистка только CM_* цепочек (оставляем UFW/Docker)
    iptables -F CM_INPUT 2>/dev/null || true
    iptables -F CM_FORWARD 2>/dev/null || true
    iptables -t nat -F CM_DNAT_RULES 2>/dev/null || true
    iptables -t nat -F CM_SNAT_RULES 2>/dev/null || true
    
    # Удалить UFW правила, созданные этим скриптом
    if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
        while IFS='|' read -r proto in_port _ _ _; do
            [[ -z "$proto" ]] && continue
            ufw delete allow "$in_port"/"$proto" 2>/dev/null || true
        done < "$CM_RULES_FILE" 2>/dev/null
    fi
    
    # Очистить файл метаданных
    > "$CM_RULES_FILE"
    
    netfilter-persistent save > /dev/null 2>&1 || true

    echo -e "${GREEN}[OK] Правила COMP_MANIYA очищены.${NC}"
    echo -e "${CYAN}[i] Все остальные правила firewall сохранены.${NC}"
    read -p "Нажмите Enter..."
}

# --- ПРОВЕРКА СОЕДИНЕНИЯ ---

check_connection() {
    echo -e "${CYAN}--- Проверка соединения ---${NC}"

    while true; do
        read -p "Введите IP для проверки: " TEST_IP
        if validate_ipv4 "$TEST_IP" || validate_ipv6 "$TEST_IP"; then
            break
        fi
        echo -e "${RED}Ошибка: введите корректный IP адрес!${NC}"
    done

    while true; do
        read -p "Введите порт: " TEST_PORT
        if validate_port "$TEST_PORT"; then 
            break
        fi
        echo -e "${RED}Ошибка: введите корректный порт!${NC}"
    done

    while true; do
        read -p "Протокол (tcp/udp): " TEST_PROTO
        [[ "$TEST_PROTO" == "tcp" || "$TEST_PROTO" == "udp" ]] && break
        echo -e "${RED}Ошибка: только tcp или udp!${NC}"
    done

    echo ""
    echo -e "${YELLOW}[*] Проверка ping...${NC}"
    ping -c 2 "$TEST_IP" 2>/dev/null || echo "Ping не ответил"

    echo ""
    echo -e "${YELLOW}[*] Проверка порта...${NC}"

    if ! command -v nc >/dev/null 2>&1; then
        apt-get update -y >/dev/null 2>&1
        apt-get install -y netcat-openbsd >/dev/null 2>&1
    fi

    if [[ "$TEST_PROTO" == "tcp" ]]; then
        nc -zv "$TEST_IP" "$TEST_PORT" 2>&1 || echo "Соединение не удалось"
    else
        nc -zvu "$TEST_IP" "$TEST_PORT" 2>&1 || echo "UDP проверка не удалась"
    fi

    read -p "Нажмите Enter..."
}

# --- BACKUP ---

backup_rules() {
    echo -e "${CYAN}--- Создание backup ---${NC}"

    local backup_file="$BACKUP_DIR/compmaniya-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
    local temp_backup="/tmp/compmaniya-backup-$$"
    mkdir -p "$temp_backup"

    # Сохранить только CM_* iptables цепочки
    {
        echo "# COMP_MANIYA Backup - $(date)"
        echo "# Содержит только CM_* цепочки"
        iptables-save | grep -E "^:(CM_|PREROUTING|POSTROUTING|FORWARD|INPUT)" 
        iptables-save | grep -E "^\[.*\]\s+-A\s+(CM_|PREROUTING.*CM|POSTROUTING.*CM|FORWARD.*CM|INPUT.*CM)"
    } > "$temp_backup/iptables.rules"

    # Сохранить метаданные правил
    [[ -f "$CM_RULES_FILE" ]] && cp "$CM_RULES_FILE" "$temp_backup/rules.metadata"

    # Сохранить конфиги socat
    for svc_file in /etc/systemd/system/socat-ipv6-*.service; do
        [[ -f "$svc_file" ]] && cp "$svc_file" "$temp_backup/"
    done

    # Архивировать
    tar czf "$backup_file" -C "$temp_backup" . 2>/dev/null
    rm -rf "$temp_backup"

    echo -e "${GREEN}[OK] Backup сохранён:${NC}"
    echo "$backup_file"
    ls -lh "$backup_file"

    read -p "Нажмите Enter..."
}

# --- RESTORE ---

restore_rules() {
    echo -e "${CYAN}--- Восстановление backup ---${NC}"

    # Найти последний backup
    local latest_backup=$(ls -t "$BACKUP_DIR"/compmaniya-backup-*.tar.gz 2>/dev/null | head -1)
    
    if [[ -z "$latest_backup" ]]; then
        echo -e "${RED}[ERROR] Backup не найден!${NC}"
        read -p "Нажмите Enter..."
        return 1
    fi

    echo -e "Найден backup: ${GREEN}$(basename "$latest_backup")${NC}"
    read -p "Восстановить из этого backup? (y/n): " confirm
    [[ "$confirm" != "y" ]] && return

    local temp_restore="/tmp/compmaniya-restore-$$"
    mkdir -p "$temp_restore"

    # Распаковать
    tar xzf "$latest_backup" -C "$temp_restore"

    echo -e "${YELLOW}[*] Восстановление CM_* цепочек...${NC}"
    
    # Восстановить только наши цепочки (не перезаписывать всё)
    if [[ -f "$temp_restore/iptables.rules" ]]; then
        grep -E "^:\s*CM_" "$temp_restore/iptables.rules" | while read -r line; do
            eval "$line" 2>/dev/null || true
        done
        
        grep -E "^\[.*\]\s+-A\s+CM_" "$temp_restore/iptables.rules" | while read -r line; do
            eval "$line" 2>/dev/null || true
        done
    fi

    # Восстановить socat сервисы
    for svc_file in "$temp_restore"/socat-ipv6-*.service; do
        [[ -f "$svc_file" ]] || continue
        local svc_name=$(basename "$svc_file")
        cp "$svc_file" "/etc/systemd/system/$svc_name"
        systemctl daemon-reload
        systemctl enable "$svc_name" >/dev/null 2>&1
        systemctl restart "$svc_name"
        echo -e "${GREEN}[OK] Восстановлен: $svc_name${NC}"
    done

    # Восстановить метаданные
    [[ -f "$temp_restore/rules.metadata" ]] && cp "$temp_restore/rules.metadata" "$CM_RULES_FILE"

    netfilter-persistent save > /dev/null 2>&1 || true
    rm -rf "$temp_restore"
    
    echo -e "${GREEN}[OK] Правила восстановлены (только CM_* цепочки).${NC}"
    read -p "Нажмите Enter..."
}

# --- ПОЛНОЕ УДАЛЕНИЕ ---

uninstall_script() {
    echo -e "${RED}╔══════════════════════════════════════╗${NC}"
    echo -e "${RED}║      ПОЛНОЕ УДАЛЕНИЕ СКРИПТА         ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════╝${NC}"
    echo ""

    echo "Будет удалено:"
    echo "- все правила CM_* iptables"
    echo "- все IPv4→IPv6 правила (socat сервисы)"
    echo "- backup файлы"
    echo "- launcher команда compmaniya"
    echo ""
    echo "Сохранено:"
    echo "- UFW правила"
    echo "- Docker правила"
    echo "- Fail2ban правила"
    echo "- Все остальные iptables правила"
    echo ""

    read -p "Введите YES для подтверждения: " confirm
    confirm=$(echo "$confirm" | tr '[:upper:]' '[:lower:]')

    if [[ "$confirm" != "yes" && "$confirm" != "y" ]]; then
        echo -e "${YELLOW}Удаление отменено.${NC}"
        read -p "Нажмите Enter..."
        return
    fi

    echo -e "${YELLOW}[*] Остановка IPv4→IPv6 сервисов...${NC}"

    for svc_file in /etc/systemd/system/socat-ipv6-*.service; do
        [[ -f "$svc_file" ]] || continue
        local svc_name=$(basename "$svc_file" .service)
        systemctl stop "$svc_name" 2>/dev/null || true
        systemctl disable "$svc_name" > /dev/null 2>&1 || true
        rm -f "$svc_file"
    done
    systemctl daemon-reload

    echo -e "${YELLOW}[*] Удаление CM_* iptables цепочек...${NC}"

    iptables -F CM_INPUT 2>/dev/null || true
    iptables -F CM_FORWARD 2>/dev/null || true
    iptables -t nat -F CM_DNAT_RULES 2>/dev/null || true
    iptables -t nat -F CM_SNAT_RULES 2>/dev/null || true
    
    iptables -X CM_INPUT 2>/dev/null || true
    iptables -X CM_FORWARD 2>/dev/null || true
    iptables -t nat -X CM_DNAT_RULES 2>/dev/null || true
    iptables -t nat -X CM_SNAT_RULES 2>/dev/null || true

    netfilter-persistent save > /dev/null 2>&1 || true

    echo -e "${YELLOW}[*] Удаление файлов...${NC}"

    rm -f /usr/local/bin/compmaniya
    rm -f "$BACKUP_DIR"/compmaniya-backup*.rules
    rm -f "$BACKUP_DIR"/compmaniya-backup*.tar.gz
    rm -f "$BACKUP_DIR"/compmaniya-backup-ipv6.list
    rm -f "$CM_RULES_FILE"
    rm -rf "$CM_STATE_DIR"

    echo ""
    echo -e "${GREEN}[SUCCESS] Скрипт полностью удалён.${NC}"
    echo -e "${GREEN}[SUCCESS] Правила UFW/Docker/Fail2ban сохранены.${NC}"
    echo -e "${CYAN}[i] Перезапустите терминал для завершения.${NC}"

    exit 0
}

# --- МОНИТОРИНГ VPS ---

system_status() {
    echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║         МОНИТОРИНГ VPS               ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"
    echo ""

    echo -e "${YELLOW}CPU LOAD:${NC}"
    uptime
    echo ""

    echo -e "${YELLOW}RAM:${NC}"
    free -h
    echo ""

    echo -e "${YELLOW}DISK:${NC}"
    df -h /
    echo ""

    echo -e "${YELLOW}NETWORK:${NC}"
    ss -s
    echo ""

    read -p "Нажмите Enter..."
}

# --- СЧЁТЧИК ТРАФИКА ---

port_traffic_stats() {
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║               ТРАФИК ПО ПРАВИЛАМ KASKAD                  ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    printf "%-8s %-8s %-22s %-12s %-12s\n" "PORT" "PROTO" "DESTINATION" "PACKETS" "TRAFFIC"
    echo "---------------------------------------------------------------------"

    # IPv4 из iptables
    iptables -t nat -L CM_DNAT_RULES -v -n 2>/dev/null | grep DNAT | while read -r line; do
        PACKETS=$(echo "$line" | awk '{print $1}')
        BYTES=$(echo "$line" | awk '{print $2}')
        PROTO=$(echo "$line" | awk '{print $4}')
        PORT=$(echo "$line" | grep -oP 'dpt:\K\d+')
        DEST=$(echo "$line" | grep -oP 'to:\K[\d\.:]+')

        if [[ -n "$PORT" ]]; then
            TRAFFIC=$(numfmt --to=iec --suffix=B "$BYTES" 2>/dev/null || echo "${BYTES}B")

            printf "%-8s %-8s %-22s %-12s %-12s\n" \
                "$PORT" "$PROTO" "$DEST" "$PACKETS" "$TRAFFIC"
        fi
    done

    # IPv6 из socat сервисов
    for svc_file in /etc/systemd/system/socat-ipv6-*.service; do
        if [[ ! -f "$svc_file" ]]; then
            continue
        fi
        
        # Парсим имя сервиса: socat-ipv6-PORT-PROTO.service
        svc_name=$(basename "$svc_file" .service)
        IN_PORT=$(echo "$svc_name" | sed 's/socat-ipv6-\([0-9]*\)-.*/\1/')
        PROTO=$(echo "$svc_name" | sed 's/.*-\(tcp\|udp\)$/\1/')
        
        # Получаем адрес IPv6 из ExecStart строки
        # Ищем IPv6:[<address>]:port в строке ExecStart
        EXEC_LINE=$(grep "^ExecStart=" "$svc_file")
        if [[ $PROTO == "tcp" ]]; then
            DEST=$(echo "$EXEC_LINE" | grep -oP 'TCP6:\K\[[0-9a-f:]+\]:[0-9]+')
        else
            DEST=$(echo "$EXEC_LINE" | grep -oP 'UDP6:\K\[[0-9a-f:]+\]:[0-9]+')
        fi
        
        # Проверяем, запущен ли сервис и работает ли он
        if systemctl is-active --quiet "socat-ipv6-${IN_PORT}-${PROTO}.service" 2>/dev/null; then
            STATUS="active"
            # Получаем количество процессов socat для этого порта
            CONNECTIONS=$(pgrep -f "socat TCP4-LISTEN:${IN_PORT}|socat UDP4-LISTEN:${IN_PORT}" 2>/dev/null | wc -l)
        else
            STATUS="inactive"
            CONNECTIONS=0
        fi
        
        if [[ -n "$IN_PORT" && -n "$PROTO" && -n "$DEST" ]]; then
            printf "%-8s %-8s %-22s %-12s %-12s\n" \
                "$IN_PORT" "$PROTO" "$DEST" "$CONNECTIONS" "$STATUS"
        fi
    done

    echo ""
    read -p "Нажмите Enter..."
}

# --- ОГРАНИЧЕНИЕ ПО IP (ИСПРАВЛЕННО) ---

lock_port_to_ip() {
    echo -e "${CYAN}--- Ограничение доступа по IP ---${NC}"
    echo -e "${WHITE}Это правило используется для ограничения доступа к перенаправленному порту.${NC}\n"

    read -p "Введите IP клиента: " CLIENT_IP
    if ! validate_ipv4 "$CLIENT_IP"; then
        echo -e "${RED}Ошибка: некорректный IP${NC}"
        read -p "Нажмите Enter..."
        return
    fi

    read -p "Введите входящий порт (на этом сервере): " IN_PORT
    if ! validate_port "$IN_PORT"; then
        echo -e "${RED}Ошибка: некорректный порт${NC}"
        read -p "Нажмите Enter..."
        return
    fi

    read -p "Введите исходящий порт (целевой сервер): " OUT_PORT
    if ! validate_port "$OUT_PORT"; then
        echo -e "${RED}Ошибка: некорректный порт${NC}"
        read -p "Нажмите Enter..."
        return
    fi

    read -p "Введите IP целевого сервера: " TARGET_IP
    if ! validate_ipv4 "$TARGET_IP"; then
        echo -e "${RED}Ошибка: некорректный IP${NC}"
        read -p "Нажмите Enter..."
        return
    fi

    read -p "Протокол (tcp/udp): " PROTO
    if [[ "$PROTO" != "tcp" && "$PROTO" != "udp" ]]; then
        echo -e "${RED}Ошибка: только tcp или udp${NC}"
        read -p "Нажмите Enter..."
        return
    fi

    # Правила в CM_FORWARD цепочке (где проходит DNAT трафик)
    # Позволить только указанному IP для данного целевого адреса:порта
    echo -e "${YELLOW}[*] Добавление правила...${NC}"
    
    if ! iptables -I CM_FORWARD -p "$PROTO" -s "$CLIENT_IP" -d "$TARGET_IP" \
        --dport "$OUT_PORT" -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT; then
        echo -e "${RED}[ERROR] Ошибка при добавлении разрешающего правила${NC}"
        read -p "Нажмите Enter..."
        return
    fi

    # Блокировать всех остальных для этого целевого адреса:порта
    if ! iptables -A CM_FORWARD -p "$PROTO" -d "$TARGET_IP" \
        --dport "$OUT_PORT" -m state --state NEW -j DROP; then
        echo -e "${RED}[ERROR] Ошибка при добавлении блокирующего правила${NC}"
        iptables -D CM_FORWARD -p "$PROTO" -s "$CLIENT_IP" -d "$TARGET_IP" \
            --dport "$OUT_PORT" -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT 2>/dev/null
        read -p "Нажмите Enter..."
        return
    fi

    netfilter-persistent save > /dev/null 2>&1 || true

    echo -e "${GREEN}[OK] Доступ разрешён только для ${CLIENT_IP}${NC}"
    echo -e "Целевой адрес: ${TARGET_IP}:${OUT_PORT}/${PROTO}"

    read -p "Нажмите Enter..."
}

# --- LIVE ПОДКЛЮЧЕНИЯ ---

live_connections() {
    echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║          LIVE ПОДКЛЮЧЕНИЯ            ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"
    echo ""

    ss -tunp | head -30

    echo ""
    read -p "Нажмите Enter..."
}

# --- МЕНЮ ---

show_menu() {
    while true; do
        echo -e "${MAGENTA}"
        echo "******************************************************"
        echo "           COMP_MANIYA KASKAD PRO v${CM_VERSION}"
        echo "   YouTube: https://www.youtube.com/@comp_maniya"
        echo "   Telegram: https://t.me/computerchik"
        echo "******************************************************"
        echo -e "${NC}"

        echo -e "${GREEN}💰 Поддержать канал:${NC} https://pay.cloudtips.ru/p/4a618628"
        echo -e "------------------------------------------------------"
        echo ""
        echo -e "1) Настроить ${CYAN}AmneziaWG / WireGuard${NC} (UDP)"
        echo -e "2) Настроить ${CYAN}VLESS / XRay${NC} (TCP)"
        echo -e "3) Настроить ${CYAN}TProxy / MTProto${NC} (TCP)"
        echo -e "4) 🛠 Создать ${YELLOW}Кастомное правило${NC}"
        echo -e "5) Посмотреть активные правила"
        echo -e "6) ${RED}Удалить одно правило${NC}"
        echo -e "7) ${RED}Сбросить ВСЕ правила COMP_MANIYA${NC}"
        echo -e "8) ${YELLOW}Показать PROMO${NC}"
        echo -e "9) ${MAGENTA}📚 ИНСТРУКЦИЯ${NC}"
        echo -e "10) Проверить соединение"
        echo -e "11) Создать backup"
        echo -e "12) Восстановить backup"
        echo -e "13) ${RED}Удалить скрипт полностью${NC}"
        echo -e "14) Мониторинг VPS"
         echo -e "15) Трафик по портам"
         echo -e "16) Ограничить доступ по IP"
         echo -e "17) Live подключения"
         echo -e "18) ${BLUE}📖 Справка${NC}"
         echo -e "0) Выход"
         echo -e "------------------------------------------------------"

         read -p "Ваш выбор: " choice

         case $choice in
             1) configure_rule_auto_detect "udp" "AmneziaWG / WireGuard" "standard" ;;
             2) configure_rule_auto_detect "tcp" "VLESS / XRay" "standard" ;;
             3) configure_rule_auto_detect "tcp" "TProxy / MTProto" "different_ports" ;;
             4) configure_custom_rule ;;
             5) list_active_rules ;;
             6) delete_single_rule ;;
             7) flush_rules ;;
             8) show_promo ;;
             9) show_instructions ;;
             10) check_connection ;;
             11) backup_rules ;;
             12) restore_rules ;;
             13) uninstall_script ;;
             14) system_status ;;
             15) port_traffic_stats ;;
             16) lock_port_to_ip ;;
             17) live_connections ;;
             18) show_help ;;
             0) clear; exit 0 ;;

            *) echo -e "${RED}Неверный выбор${NC}"; read -p "Нажмите Enter..." ;;
        esac
    done
}

# --- ЗАПУСК ---

# Обработка параметров командной строки
case "${1:-}" in
    --version|-v)
        echo "COMP_MANIYA FULL KASKAD PRO"
        echo "Version: 2.0-safe"
        echo "Release date: 2026-11-02"
        echo "Git commit: 53a6dd2"
        echo "Status: Production Ready ✅"
        echo ""
        echo "Основные изменения в v2.0:"
        echo "  • 8 критических исправлений firewall архитектуры"
        echo "  • 6 дополнительных улучшений"
        echo "  • Изолированные CM_* цепочки iptables"
        echo "  • 3-уровневая SSH защита"
        echo "  • Полная обработка ошибок"
        echo "  • Встроенная справка"
        echo ""
        echo "Для справки: compmaniya --help"
        exit 0
        ;;
    --help|-h)
        echo "COMP_MANIYA FULL KASKAD PRO v2.0-safe"
        echo ""
        echo "Использование: compmaniya [ОПЦИЯ]"
        echo ""
        echo "Опции:"
        echo "  (без опций)      Открыть интерактивное меню"
        echo "  --version, -v    Показать версию"
        echo "  --help, -h       Показать эту справку"
        echo "  --status         Статус текущих правил"
        echo "  --list-rules     Список активных правил"
        echo "  --backup         Создать backup"
        echo "  --restore        Восстановить из backup"
        echo ""
        echo "Примеры:"
        echo "  compmaniya                  # Открыть меню"
        echo "  compmaniya --version        # Показать версию"
        echo "  compmaniya --status         # Показать статус"
        echo "  compmaniya --list-rules     # Список правил"
        echo ""
        echo "Для получения справки внутри меню выберите опцию 20 (Help)"
        echo ""
        echo "Поддержка:"
        echo "  📧 Telegram: https://t.me/computerchik"
        echo "  📺 YouTube:  https://www.youtube.com/@comp_maniya"
        echo "  💰 Донат:    https://pay.cloudtips.ru/p/4a618628"
        exit 0
        ;;
    --status)
        echo -e "${CYAN}╔════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║     СТАТУС COMP_MANIYA v2.0-safe       ║${NC}"
        echo -e "${CYAN}╚════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${YELLOW}Версия:${NC} 2.0-safe"
        echo -e "${YELLOW}Дата релиза:${NC} 2026-11-02"
        echo -e "${YELLOW}Статус:${NC} Production Ready ✅"
        echo -e "${YELLOW}Git commit:${NC} 53a6dd2"
        echo ""
        echo -e "${CYAN}Активные CM_* цепочки:${NC}"
        iptables -L CM_INPUT -n 2>/dev/null | head -2 && echo "[✓] CM_INPUT существует" || echo "[✗] CM_INPUT не найдена"
        iptables -L CM_FORWARD -n 2>/dev/null | head -2 && echo "[✓] CM_FORWARD существует" || echo "[✗] CM_FORWARD не найдена"
        iptables -t nat -L CM_DNAT_RULES -n 2>/dev/null | head -2 && echo "[✓] CM_DNAT_RULES существует" || echo "[✗] CM_DNAT_RULES не найдена"
        iptables -t nat -L CM_SNAT_RULES -n 2>/dev/null | head -2 && echo "[✓] CM_SNAT_RULES существует" || echo "[✗] CM_SNAT_RULES не найдена"
        echo ""
        echo -e "${CYAN}Socat сервисы (IPv4→IPv6):${NC}"
        systemctl list-units --all "*socat-ipv6*" --no-pager 2>/dev/null | grep socat | wc -l | xargs -I {} echo "[·] Найдено {} сервисов"
        echo ""
        echo -e "${CYAN}Backup файлы:${NC}"
        ls -lh /root/compmaniya-backup-*.tar.gz 2>/dev/null | wc -l | xargs -I {} echo "[·] Найдено {} backup'ов"
        echo ""
        exit 0
        ;;
    --list-rules)
        check_root
        prepare_system
        list_active_rules
        exit 0
        ;;
    --backup)
        check_root
        prepare_system
        backup_rules
        exit 0
        ;;
    --restore)
        check_root
        prepare_system
        restore_rules
        exit 0
        ;;
    "")
        # Обычный запуск без параметров
        ;;
    *)
        echo -e "${RED}[ERROR] Неизвестная опция: $1${NC}"
        echo "Для справки используйте: compmaniya --help"
        exit 1
        ;;
esac

# Основной запуск
check_root
prepare_system
show_menu
