# Руководство по миграции COMP_MANIYA v2.0-safe → v3.0

## ⚠️ КРИТИЧЕСКОЕ ОБНОВЛЕНИЕ

Версия v3.0 исправляет **5 критических уязвимостей безопасности** из v2.0-safe:

1. **MASQUERADE** - сервер больше НЕ становится open proxy
2. **Миграция** - НЕ удаляет Docker/UFW DNAT правила
3. **Restore** - удалена RCE уязвимость (eval)
4. **Uninstall** - полная очистка без "мусора"
5. **Транзакции** - откат при ошибках применения правил

## Автоматическая миграция

При первом запуске v3.0 на системе с v2.0-safe:

1. ✅ Скрипт обнаружит установку v2.0-safe
2. ✅ Предложит выполнить миграцию
3. ✅ Создаст safety backup: `compmaniya-backup-pre-v3-migration-YYYYMMDD-HHMMSS.tar.gz`
4. ✅ Мигрирует все правила через метаданные (НЕ через парсинг iptables)
5. ✅ Добавит UUID маркеры ко всем правилам
6. ✅ Исправит MASQUERADE (критично!)
7. ✅ Создаст маркер успешной миграции

## Что изменится

### Формат метаданных правил

**v2.0-safe:**
```
proto|in_port|out_port|target_ip|name|timestamp
```

**v3.0:**
```
proto|in_port|out_port|target_ip|name|timestamp|uuid
```

### MASQUERADE правила (КРИТИЧЕСКОЕ ИЗМЕНЕНИЕ)

**v2.0-safe (ОПАСНО - создаёт open proxy):**
```bash
iptables -t nat -A CM_SNAT_RULES -d TARGET_IP -o eth0 -j MASQUERADE
```

**v3.0 (БЕЗОПАСНО):**
```bash
iptables -t nat -A CM_SNAT_RULES -o eth0 -j MASQUERADE
```

### Маркировка правил

Все правила в v3.0 получают комментарии:
```
COMP_MANIYA:v3:<uuid>:<rule_type>
```

Где:
- `uuid` - уникальный идентификатор правила
- `rule_type` - тип правила (input, dnat, fwd:in, fwd:out, masq)

Примеры:
```
COMP_MANIYA:v3:a1b2c3d4-e5f6-7890:input
COMP_MANIYA:v3:a1b2c3d4-e5f6-7890:dnat
COMP_MANIYA:v3:a1b2c3d4-e5f6-7890:fwd:in
```

### Backup формат

**v2.0-safe:** Некорректный grep вывод
**v3.0:** Правильный формат iptables-restore с SHA256 проверкой

## Процесс миграции (пошагово)

### Шаг 1: Обновление скрипта

```bash
# Скачать новую версию
cd /root
wget -O install.sh https://raw.githubusercontent.com/svu2009-prog/comp_maniya/dev-v3.0/install.sh

# Проверить версию
bash install.sh --version
# Должно показать: VERSION: 3.0
```

### Шаг 2: Запуск миграции

```bash
# Просто запустите скрипт
sudo bash install.sh

# ИЛИ если уже установлен
compmaniya
```

### Шаг 3: Подтверждение миграции

Скрипт покажет:
```
═══════════════════════════════════════════════
  Обнаружена установка v2.0-safe
  Требуется миграция на v3.0
═══════════════════════════════════════════════

Изменения в v3.0:
  • Все правила получат уникальные UUID маркеры
  • MASQUERADE исправлен (безопасность)
  • Backup/Restore полностью переработаны
  • Улучшена стабильность и безопасность

Миграция безопасна и обратима.

Начать миграцию? (y/n):
```

Введите `y` для продолжения.

### Шаг 4: Проверка после миграции

```bash
# Проверить статус
compmaniya --status

# Проверить логи
tail -f /var/log/comp_maniya/comp_maniya.log

# Просмотреть правила с UUID маркерами
iptables -t nat -L CM_DNAT_RULES -n -v | grep COMP_MANIYA

# Проверить MASQUERADE (должен быть по интерфейсу, НЕ по destination)
iptables -t nat -L CM_SNAT_RULES -n -v
```

### Шаг 5: Проверка работоспособности

Убедитесь что все ваши каскады работают:

```bash
# Список активных правил
compmaniya
# Выберите пункт 5

# Проверка соединений
compmaniya
# Выберите пункт 10
```

## Откат на v2.0-safe (если необходимо)

⚠️ **НЕ РЕКОМЕНДУЕТСЯ** - v3.0 критически важна для безопасности.

Если всё же необходимо:

```bash
# 1. Найти pre-migration backup
ls -lh /root/compmaniya-backup-pre-v3-migration-*.tar.gz

# 2. Восстановить из backup
compmaniya --restore /root/compmaniya-backup-pre-v3-migration-20261102-143022.tar.gz

# 3. Удалить маркер v3
sudo rm -f /var/lib/comp_maniya/migrated_to_v3

# 4. Вернуться к старой версии скрипта (если нужно)
cd /root
wget -O install.sh https://raw.githubusercontent.com/svu2009-prog/comp_maniya/main/install.sh
```

## Проверка после миграции

### Проверка MASQUERADE (КРИТИЧНО!)

```bash
# Проверить MASQUERADE правила
iptables -t nat -L CM_SNAT_RULES -n -v

# ПРАВИЛЬНО (v3.0):
# Chain CM_SNAT_RULES (1 references)
# ...  MASQUERADE  all  --  *    eth0    0.0.0.0/0    0.0.0.0/0    /* COMP_MANIYA:v3:masq:eth0 */

# НЕПРАВИЛЬНО (v2.0):
# Chain CM_SNAT_RULES (1 references)
# ...  MASQUERADE  all  --  *    eth0    0.0.0.0/0    TARGET_IP    /* (без комментария) */
```

### Проверка маркировки правил

```bash
# Все правила должны иметь комментарии COMP_MANIYA:v3:uuid
iptables -L CM_INPUT -n -v | grep "COMP_MANIYA:v3"
iptables -L CM_FORWARD -n -v | grep "COMP_MANIYA:v3"
iptables -t nat -L CM_DNAT_RULES -n -v | grep "COMP_MANIYA:v3"
```

### Проверка метаданных

```bash
# Проверить формат метаданных (должен быть v3 с UUID)
cat /root/.comp_maniya_rules

# Формат v3: proto|in_port|out_port|target_ip|name|timestamp|uuid
# Пример: tcp|8080|443|1.2.3.4|Test Rule|1730585734|a1b2c3d4-e5f6-7890
```

### Проверка логов

```bash
# Логи должны создаваться в новом месте
ls -lh /var/log/comp_maniya/comp_maniya.log

# Проверить последние записи
tail -20 /var/log/comp_maniya/comp_maniya.log
```

## Часто задаваемые вопросы

### В: Безопасна ли миграция?

Да. Миграция:
- Создаёт safety backup перед началом
- Читает метаданные, НЕ парсит iptables
- НЕ трогает Docker/UFW/Fail2ban правила
- Обратима через restore

### В: Что произойдёт с моими существующими правилами?

Все правила сохранятся и получат:
- UUID маркеры
- Исправленный MASQUERADE
- Комментарии для отслеживания

### В: Нужно ли мне делать backup вручную?

Нет. Скрипт автоматически создаёт safety backup перед миграцией.

### В: Как долго длится миграция?

Обычно 10-30 секунд в зависимости от количества правил.

### В: Что делать если миграция не удалась?

1. Проверьте логи: `/var/log/comp_maniya/comp_maniya.log`
2. Найдите safety backup: `ls /root/compmaniya-backup-pre-v3-migration-*.tar.gz`
3. Восстановите: `compmaniya --restore <backup_file>`
4. Сообщите об ошибке: https://t.me/computerchik

### В: Изменится ли работа моих каскадов?

Нет. Все каскады продолжат работать без изменений.  
Единственное отличие - правильный MASQUERADE повысит безопасность.

### В: Нужно ли обновлять клиентские конфигурации?

Нет. Клиентские конфигурации не требуют изменений.

### В: Как проверить что v3.0 установлена?

```bash
compmaniya --version
# Должно показать: VERSION: 3.0

# ИЛИ
cat /var/lib/comp_maniya/migrated_to_v3
# Файл должен существовать
```

## Поддержка

Если возникли проблемы с миграцией:

- 📧 Telegram: https://t.me/computerchik
- 📺 YouTube: https://www.youtube.com/@comp_maniya
- 🐛 GitHub Issues: https://github.com/svu2009-prog/comp_maniya/issues

## Заключение

Миграция на v3.0 - **критически важна** для безопасности вашего сервера.

Основные преимущества v3.0:
- ✅ НЕТ open proxy уязвимости
- ✅ НЕТ RCE уязвимости в restore
- ✅ Безопасная миграция
- ✅ Полная очистка при uninstall
- ✅ Транзакционность с откатом
- ✅ UUID отслеживание всех правил
- ✅ Подробное логирование

**Рекомендуется обновиться как можно скорее.**
