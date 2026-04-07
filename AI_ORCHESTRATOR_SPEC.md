# Техническое задание: Система оркестрации AI-агентов (Codex + Qwen)

**Версия:** 1.0  
**Дата:** 2026-04-07  
**Статус:** Готов к разработке

---

## 📋 Оглавление

1. [Цель и требования](#цель-и-требования)
2. [Архитектура](#архитектура)
3. [Структура файлов](#структура-файлов)
4. [Исходный код](#исходный-код)
5. [Инструкция по установке](#инструкция-по-установке)
6. [Инструкция по использованию](#инструкция-по-использованию)
7. [API и интеграция](#api-и-интеграция)
8. [Отладка и мониторинг](#отладка-и-мониторинг)
9. [Расширение системы](#расширение-системы)

---

## 🎯 Цель и требования

### Бизнес-цель
Автоматизировать процесс разработки с двумя AI-агентами:
- **Исполнитель (Codex)** - пишет код
- **Проверяющий (Qwen)** - делает code review
- **Оркестратор** - управляет циклом без ручного вмешательства

### Ключевые требования
1. ✅ Агенты работают в разных CLI-окнах
2. ✅ Автоматический цикл: код → проверка → баг → исправление
3. ✅ Максимум 3 итерации исправлений
4. ✅ Логирование всех действий
5. ✅ Возможность ручного создания задач
6. ✅ Мониторинг статуса в реальном времени

### Технические требования
- **ОС:** Ubuntu 20.04+ / Debian 11+ / WSL2
- **CLI модели:** Codex CLI, Qwen CLI (или Ollama)
- **Зависимости:** bash 4+, coreutils, grep, sed
- **Память:** 4GB RAM минимум

---

## 🏗 Архитектура

### Общая схема
┌─────────────────────────────────────────────────────────┐
│ ОРКЕСТРАТОР (orchestrator.sh) │
│ - Мониторинг задач │
│ - UI в реальном времени │
│ - Создание новых задач │
└────────────┬──────────────────────────────┬────────────┘
│ │
┌────────▼────────┐ ┌────────▼────────┐
│ ИСПОЛНИТЕЛЬ │ │ ПРОВЕРЯЮЩИЙ │
│ (executor.sh) │◄───────────│ (reviewer.sh) │
│ │ (bug) │ │
│ Codex CLI ├───────────►│ Qwen CLI │
│ │ (review) │ │
└────────┬────────┘ └────────┬────────┘
│ │
└──────────┬───────────────────┘
▼
┌─────────────────┐
│ ФАЙЛОВАЯ СИСТЕМА │
│ ./workspace/ │
│ - tasks/ │
│ - completed/ │
│ - logs/ │
└─────────────────┘

text

### Машина состояний задачи
┌─────────┐
│ pending │ (новая задача)
└────┬────┘
│ executor
▼
┌─────────┐
│ working │ (Codex пишет код)
└────┬────┘
│
▼
┌─────────┐
│ review │ (ожидает проверки)
└────┬────┘
│ reviewer
▼
┌─────────┐
│ OK? │
└┬───────┬┘
│ Yes │ No (баг)
▼ ▼
┌──────┐ ┌─────┐
│ done │ │ bug │
└──────┘ └──┬──┘
│ (итерация < MAX)
▼
┌─────────┐
│ working │ (исправление)
└─────────┘

text

---

## 📁 Структура файлов
ai-orchestrator/
│
├── orchestrator.sh # Главный оркестратор (755)
├── start_all.sh # Быстрый запуск (755)
├── README.md # Документация
│
├── agents/
│ ├── common.sh # Общие функции (644)
│ ├── executor.sh # Агент-исполнитель (755)
│ └── reviewer.sh # Агент-проверяющий (755)
│
├── config/
│ └── agents.conf # Конфигурация (644)
│
├── workspace/
│ ├── tasks/ # Активные задачи
│ ├── completed/ # Завершённые задачи
│ └── logs/ # Логи агентов
│
├── tests/
│ ├── test_executor.sh # Тесты исполнителя
│ ├── test_reviewer.sh # Тесты проверяющего
│ └── fixtures/ # Тестовые данные
│
└── tools/
├── cleanup.sh # Очистка workspace
├── backup.sh # Бэкап задач
└── stats.sh # Статистика выполнения

text

---

## 💻 Исходный код

### 1. Файл конфигурации

**`config/agents.conf`**
```bash
# Пути к CLI моделям
CODEX_CMD="codex"
QWEN_CMD="qwen"

# Альтернативные команды (раскомментировать при необходимости)
# CODEX_CMD="copilot"
# QWEN_CMD="ollama run qwen:7b"

# Параметры выполнения
MAX_ITERATIONS=3                # Максимум циклов исправления
REVIEW_TIMEOUT=30               # Таймаут проверки (секунд)
WORK_TIMEOUT=120                # Таймаут выполнения (секунд)

# Параметры моделей
CODEX_TEMPERATURE=0.7
QWEN_TEMPERATURE=0.3
CODEX_MAX_TOKENS=2000
QWEN_MAX_TOKENS=1000

# Системные настройки
LOG_LEVEL="INFO"                # DEBUG, INFO, ERROR
MONITOR_REFRESH=2               # Секунд между обновлением UI
MAX_PARALLEL_TASKS=3            # Максимум параллельных задач
2. Общие функции
agents/common.sh

bash
#!/bin/bash

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Глобальные переменные
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
WORKSPACE="$PROJECT_ROOT/workspace"
CONFIG_FILE="$PROJECT_ROOT/config/agents.conf"

# Загрузка конфигурации
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    else
        echo -e "${RED}Ошибка: Конфиг не найден $CONFIG_FILE${NC}"
        exit 1
    fi
}

# Функция логирования
log() {
    local agent=$1
    local level=$2
    local msg=$3
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Проверка уровня логирования
    if [[ "$LOG_LEVEL" == "DEBUG" ]] || [[ "$level" != "DEBUG" ]]; then
        echo "[$timestamp] [$agent] [$level] $msg" >> "$WORKSPACE/logs/${agent}.log"
        
        # Вывод в консоль для важных сообщений
        if [[ "$level" == "ERROR" ]]; then
            echo -e "${RED}[$agent] $msg${NC}" >&2
        elif [[ "$level" == "WARNING" ]]; then
            echo -e "${YELLOW}[$agent] $msg${NC}"
        fi
    fi
}

# Получить следующую задачу по статусу
get_task_by_status() {
    local status=$1
    local task_found=""
    
    for task_dir in "$WORKSPACE/tasks"/task_*/; do
        if [ -d "$task_dir" ] && [ -f "$task_dir/status.txt" ]; then
            current_status=$(cat "$task_dir/status.txt" 2>/dev/null)
            if [ "$current_status" == "$status" ]; then
                task_found="$task_dir"
                break
            fi
        fi
    done
    
    echo "$task_found"
}

# Получить все задачи по статусу (для параллельного выполнения)
get_tasks_by_status() {
    local status=$1
    local tasks=()
    
    for task_dir in "$WORKSPACE/tasks"/task_*/; do
        if [ -d "$task_dir" ] && [ -f "$task_dir/status.txt" ]; then
            current_status=$(cat "$task_dir/status.txt" 2>/dev/null)
            if [ "$current_status" == "$status" ]; then
                tasks+=("$task_dir")
            fi
        fi
    done
    
    printf '%s\n' "${tasks[@]}"
}

# Обновить статус задачи
update_status() {
    local task_dir=$1
    local new_status=$2
    local task_id=$(basename "$task_dir")
    
    echo "$new_status" > "$task_dir/status.txt"
    log "system" "INFO" "Task $task_id: $new_status"
}

# Получить текущую итерацию
get_iteration() {
    local task_dir=$1
    local iter=$(cat "$task_dir/iteration" 2>/dev/null || echo "0")
    echo "$iter"
}

# Увеличить итерацию
increment_iteration() {
    local task_dir=$1
    local iter=$(get_iteration "$task_dir")
    iter=$((iter + 1))
    echo "$iter" > "$task_dir/iteration"
    echo "$iter"
}

# Проверка таймаута
check_timeout() {
    local task_dir=$1
    local timeout_seconds=$2
    local start_file="$task_dir/start_time"
    
    if [ -f "$start_file" ]; then
        local start_time=$(cat "$start_file")
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [ $elapsed -gt $timeout_seconds ]; then
            return 0  # Таймаут
        fi
    fi
    return 1  # Нет таймаута
}

# Установить время начала
set_start_time() {
    local task_dir=$1
    date +%s > "$task_dir/start_time"
}

# Очистить время начала
clear_start_time() {
    local task_dir=$1
    rm -f "$task_dir/start_time"
}

# Загрузка конфигурации при старте
load_config
3. Агент-исполнитель (Codex)
agents/executor.sh

bash
#!/bin/bash

source "$(dirname "$0")/common.sh"

# Глобальные переменные
EXECUTOR_NAME="executor"
RUNNING=true
MAX_PARALLEL=${MAX_PARALLEL_TASKS:-3}

# Обработка сигналов
cleanup() {
    log "$EXECUTOR_NAME" "INFO" "Получен сигнал остановки"
    RUNNING=false
    exit 0
}

trap cleanup SIGTERM SIGINT

# Выполнение задачи через Codex
execute_with_codex() {
    local task_dir=$1
    local prompt=$2
    local output_file="$task_dir/code/output.txt"
    
    log "$EXECUTOR_NAME" "DEBUG" "Вызов Codex с промптом: ${#prompt} символов"
    
    # Создаем временный файл с промптом
    local temp_prompt="/tmp/codex_prompt_$$.txt"
    echo "$prompt" > "$temp_prompt"
    
    # Вызов Codex CLI
    local start_time=$(date +%s)
    if $CODEX_CMD --temperature $CODEX_TEMPERATURE \
                   --max-tokens $CODEX_MAX_TOKENS \
                   --input "$temp_prompt" \
                   --output "$output_file" 2>> "$WORKSPACE/logs/codex_errors.log"; then
        
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        log "$EXECUTOR_NAME" "INFO" "Codex выполнил задачу за ${duration} секунд"
        rm -f "$temp_prompt"
        return 0
    else
        local exit_code=$?
        log "$EXECUTOR_NAME" "ERROR" "Codex завершился с ошибкой $exit_code"
        rm -f "$temp_prompt"
        return 1
    fi
}

# Обработка одной задачи
process_task() {
    local task_dir=$1
    local task_id=$(basename "$task_dir")
    
    log "$EXECUTOR_NAME" "INFO" "Начало обработки задачи $task_id"
    
    # Получаем текущую итерацию
    local iteration=$(get_iteration "$task_dir")
    iteration=$(increment_iteration "$task_dir")
    
    # Устанавливаем время начала
    set_start_time "$task_dir"
    
    # Обновляем статус
    update_status "$task_dir" "working"
    
    # Читаем промпт
    local prompt=$(cat "$task_dir/prompt.txt" 2>/dev/null)
    if [ -z "$prompt" ]; then
        log "$EXECUTOR_NAME" "ERROR" "Промпт не найден в $task_dir"
        update_status "$task_dir" "error"
        clear_start_time "$task_dir"
        return 1
    fi
    
    # Добавляем контекст из предыдущего ревью (если есть баг)
    if [ -f "$task_dir/review.txt" ] && [ $iteration -gt 1 ]; then
        local bug_context=$(cat "$task_dir/review.txt")
        prompt="${prompt}\n\nИСПРАВЬ СЛЕДУЮЩИЕ ОШИБКИ:\n${bug_context}\n\nПожалуйста, предоставь исправленную версию."
        log "$EXECUTOR_NAME" "DEBUG" "Добавлен контекст исправления (итерация $iteration)"
    fi
    
    # Создаем директорию для кода если её нет
    mkdir -p "$task_dir/code"
    
    # Выполняем задачу
    if execute_with_codex "$task_dir" "$prompt"; then
        log "$EXECUTOR_NAME" "INFO" "Задача $task_id успешно выполнена (итерация $iteration)"
        update_status "$task_dir" "review"
        clear_start_time "$task_dir"
        return 0
    else
        log "$EXECUTOR_NAME" "ERROR" "Ошибка выполнения задачи $task_id"
        update_status "$task_dir" "error"
        clear_start_time "$task_dir"
        return 1
    fi
}

# Мониторинг и обработка задач (с поддержкой параллелизма)
process_tasks_loop() {
    log "$EXECUTOR_NAME" "INFO" "Запущен с MAX_PARALLEL=$MAX_PARALLEL"
    
    while $RUNNING; do
        # Сначала ищем задачи с багами (приоритет выше)
        local bug_tasks=()
        while IFS= read -r task; do
            bug_tasks+=("$task")
        done < <(get_tasks_by_status "bug")
        
        # Затем задачи в статусе pending
        local pending_tasks=()
        while IFS= read -r task; do
            pending_tasks+=("$task")
        done < <(get_tasks_by_status "pending")
        
        # Объединяем списки (bug имеют приоритет)
        local all_tasks=("${bug_tasks[@]}" "${pending_tasks[@]}")
        
        # Ограничиваем количество параллельных задач
        local running_count=$(jobs -r | wc -l)
        local available_slots=$((MAX_PARALLEL - running_count))
        
        if [ $available_slots -gt 0 ] && [ ${#all_tasks[@]} -gt 0 ]; then
            local tasks_to_process=${#all_tasks[@]}
            if [ $tasks_to_process -gt $available_slots ]; then
                tasks_to_process=$available_slots
            fi
            
            for ((i=0; i<$tasks_to_process; i++)); do
                local task="${all_tasks[$i]}"
                log "$EXECUTOR_NAME" "DEBUG" "Запуск обработки $(basename "$task")"
                process_task "$task" &
            done
        fi
        
        sleep 2
    done
}

# Проверка таймаутов
check_timeouts_loop() {
    while $RUNNING; do
        for task_dir in "$WORKSPACE/tasks"/task_*/; do
            if [ -d "$task_dir" ]; then
                local status=$(cat "$task_dir/status.txt" 2>/dev/null)
                if [ "$status" == "working" ]; then
                    if check_timeout "$task_dir" $WORK_TIMEOUT; then
                        local task_id=$(basename "$task_dir")
                        log "$EXECUTOR_NAME" "WARNING" "Таймаут задачи $task_id"
                        update_status "$task_dir" "timeout"
                        clear_start_time "$task_dir"
                    fi
                fi
            fi
        done
        sleep 10
    done
}

# Основной цикл
main() {
    log "$EXECUTOR_NAME" "INFO" "Агент-исполнитель (Codex) запущен"
    log "$EXECUTOR_NAME" "INFO" "Конфигурация: CODEX_CMD=$CODEX_CMD, TEMP=$CODEX_TEMPERATURE"
    
    # Запускаем обработчик таймаутов в фоне
    check_timeouts_loop &
    local timeout_pid=$!
    
    # Запускаем основной цикл обработки
    process_tasks_loop
    
    # Очистка
    kill $timeout_pid 2>/dev/null
    log "$EXECUTOR_NAME" "INFO" "Агент остановлен"
}

# Запуск
main
4. Агент-проверяющий (Qwen)
agents/reviewer.sh

bash
#!/bin/bash

source "$(dirname "$0")/common.sh"

# Глобальные переменные
REVIEWER_NAME="reviewer"
RUNNING=true

# Обработка сигналов
cleanup() {
    log "$REVIEWER_NAME" "INFO" "Получен сигнал остановки"
    RUNNING=false
    exit 0
}

trap cleanup SIGTERM SIGINT

# Проверка через Qwen
review_with_qwen() {
    local task_dir=$1
    local code_output=$2
    local review_file="$task_dir/review.txt"
    
    log "$REVIEWER_NAME" "DEBUG" "Вызов Qwen для проверки"
    
    # Создаем промпт для Qwen
    local prompt_file="/tmp/qwen_review_$$.txt"
    cat > "$prompt_file" << EOF
Ты — эксперт по code review. Проанализируй следующий код и найди все проблемы.

КОД ДЛЯ ПРОВЕРКИ:
\`\`\`
$code_output
\`\`\`

ТРЕБОВАНИЯ К ПРОВЕРКЕ:
1. Синтаксические ошибки
2. Логические ошибки и баги
3. Потенциальные проблемы производительности
4. Соответствие лучшим практикам
5. Безопасность

ФОРМАТ ОТВЕТА:
- Если код идеален, ответь только: OK
- Если есть проблемы, опиши каждую проблему в формате:
  [ТИП_ОШИБКИ] Описание проблемы
  Рекомендация: как исправить

Пример ответа с ошибкой:
[ЛОГИЧЕСКАЯ] Функция не проверяет граничные условия
Рекомендация: Добавить проверку на пустой массив

ОТВЕТ:
EOF
    
    # Вызов Qwen CLI
    local start_time=$(date +%s)
    if $QWEN_CMD --temperature $QWEN_TEMPERATURE \
                 --max-tokens $QWEN_MAX_TOKENS \
                 --input "$prompt_file" \
                 --output "$review_file" 2>> "$WORKSPACE/logs/qwen_errors.log"; then
        
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        log "$REVIEWER_NAME" "INFO" "Qwen завершил проверку за ${duration} секунд"
        rm -f "$prompt_file"
        return 0
    else
        local exit_code=$?
        log "$REVIEWER_NAME" "ERROR" "Qwen завершился с ошибкой $exit_code"
        rm -f "$prompt_file"
        return 1
    fi
}

# Анализ результата проверки
analyze_review() {
    local review_file=$1
    local max_iterations=$MAX_ITERATIONS
    
    # Читаем результат проверки
    local review_content=$(cat "$review_file" 2>/dev/null)
    
    # Проверяем на OK
    if echo "$review_content" | grep -q "^OK$"; then
        echo "PASS"
        return 0
    fi
    
    # Проверяем, есть ли описание ошибок
    if echo "$review_content" | grep -q "\["; then
        echo "FAIL"
        return 1
    fi
    
    # Если не OK и нет явных ошибок, считаем что есть проблемы
    echo "FAIL"
    return 1
}

# Обработка задачи
review_task() {
    local task_dir=$1
    local task_id=$(basename "$task_dir")
    
    log "$REVIEWER_NAME" "INFO" "Начало проверки задачи $task_id"
    
    # Устанавливаем время начала
    set_start_time "$task_dir"
    
    # Обновляем статус
    update_status "$task_dir" "reviewing"
    
    # Читаем результат исполнителя
    local code_output_file="$task_dir/code/output.txt"
    if [ ! -f "$code_output_file" ]; then
        log "$REVIEWER_NAME" "ERROR" "Нет результата для проверки в $task_id"
        update_status "$task_dir" "error"
        clear_start_time "$task_dir"
        return 1
    fi
    
    local code_output=$(cat "$code_output_file")
    if [ -z "$code_output" ]; then
        log "$REVIEWER_NAME" "ERROR" "Пустой результат в $task_id"
        update_status "$task_dir" "error"
        clear_start_time "$task_dir"
        return 1
    fi
    
    # Выполняем проверку
    if review_with_qwen "$task_dir" "$code_output"; then
        # Анализируем результат
        local review_result=$(analyze_review "$task_dir/review.txt")
        local iteration=$(get_iteration "$task_dir")
        
        if [ "$review_result" == "PASS" ]; then
            log "$REVIEWER_NAME" "INFO" "Задача $task_id ПРИНЯТА (итерация $iteration)"
            update_status "$task_dir" "done"
            clear_start_time "$task_dir"
            
            # Перемещаем в завершённые
            local completed_dir="$WORKSPACE/completed/${task_id}_$(date +%Y%m%d_%H%M%S)"
            mv "$task_dir" "$completed_dir"
            log "$REVIEWER_NAME" "INFO" "Задача $task_id перемещена в $completed_dir"
            
            return 0
        else
            # Проверяем лимит итераций
            if [ $iteration -ge $max_iterations ]; then
                log "$REVIEWER_NAME" "WARNING" "Превышен лимит итераций ($max_iterations) для $task_id"
                update_status "$task_dir" "failed"
                clear_start_time "$task_dir"
            else
                log "$REVIEWER_NAME" "INFO" "Найдены баги в $task_id, отправляю на исправление"
                update_status "$task_dir" "bug"
                clear_start_time "$task_dir"
            fi
            return 1
        fi
    else
        log "$REVIEWER_NAME" "ERROR" "Ошибка при проверке $task_id"
        update_status "$task_dir" "error"
        clear_start_time "$task_dir"
        return 1
    fi
}

# Основной цикл проверки
review_loop() {
    log "$REVIEWER_NAME" "INFO" "Агент-проверяющий (Qwen) запущен"
    log "$REVIEWER_NAME" "INFO" "Конфигурация: QWEN_CMD=$QWEN_CMD, TEMP=$QWEN_TEMPERATURE"
    
    while $RUNNING; do
        # Ищем задачи со статусом review
        local task_dir=$(get_task_by_status "review")
        
        if [ -n "$task_dir" ]; then
            review_task "$task_dir"
        fi
        
        # Проверка таймаутов
        for task_dir in "$WORKSPACE/tasks"/task_*/; do
            if [ -d "$task_dir" ]; then
                local status=$(cat "$task_dir/status.txt" 2>/dev/null)
                if [ "$status" == "reviewing" ]; then
                    if check_timeout "$task_dir" $REVIEW_TIMEOUT; then
                        local task_id=$(basename "$task_dir")
                        log "$REVIEWER_NAME" "WARNING" "Таймаут проверки задачи $task_id"
                        update_status "$task_dir" "timeout"
                        clear_start_time "$task_dir"
                    fi
                fi
            fi
        done
        
        sleep 2
    done
}

# Запуск
review_loop
5. Оркестратор
orchestrator.sh

bash
#!/bin/bash

source "./agents/common.sh"

# Глобальные переменные
ORCHESTRATOR_NAME="orchestrator"
RUNNING=true

# Очистка при выходе
cleanup() {
    log "$ORCHESTRATOR_NAME" "INFO" "Остановка оркестратора"
    RUNNING=false
    exit 0
}

trap cleanup SIGTERM SIGINT

# Создание новой задачи
create_task() {
    local prompt="$1"
    local task_id=$(date +%s%N | sha256sum | head -c 8)
    local task_dir="$WORKSPACE/tasks/task_$task_id"
    
    mkdir -p "$task_dir/code"
    echo "$prompt" > "$task_dir/prompt.txt"
    echo "pending" > "$task_dir/status.txt"
    echo "0" > "$task_dir/iteration"
    
    log "$ORCHESTRATOR_NAME" "INFO" "Создана задача: task_$task_id"
    echo "task_$task_id"
}

# Показать статистику
show_stats() {
    local total=0
    local pending=0
    local working=0
    local review=0
    local bug=0
    local done=0
    local failed=0
    
    for task_dir in "$WORKSPACE/tasks"/task_*/; do
        if [ -d "$task_dir" ]; then
            total=$((total + 1))
            status=$(cat "$task_dir/status.txt" 2>/dev/null)
            case $status in
                "pending") pending=$((pending + 1)) ;;
                "working") working=$((working + 1)) ;;
                "review") review=$((review + 1)) ;;
                "bug") bug=$((bug + 1)) ;;
                "done") done=$((done + 1)) ;;
                "failed") failed=$((failed + 1)) ;;
            esac
        fi
    done
    
    echo -e "\n${BLUE}=== СТАТИСТИКА ===${NC}"
    echo -e "${CYAN}Активные задачи:${NC} $total"
    echo -e "  ${CYAN}⏳ Ожидание:${NC} $pending"
    echo -e "  ${YELLOW}⚙️  Выполнение:${NC} $working"
    echo -e "  ${PURPLE}📝 Проверка:${NC} $review"
    echo -e "  ${RED}🐛 Баги:${NC} $bug"
    echo -e "${GREEN}✅ Завершено:${NC} $(ls -1 $WORKSPACE/completed/ 2>/dev/null | wc -l)"
    echo -e "${RED}❌ Провалено:${NC} $failed"
}

# Показать список задач
show_tasks() {
    echo -e "\n${BLUE}=== АКТИВНЫЕ ЗАДАЧИ ===${NC}"
    
    if [ ! "$(ls -A $WORKSPACE/tasks 2>/dev/null)" ]; then
        echo -e "${YELLOW}Нет активных задач${NC}"
        return
    fi
    
    for task_dir in $WORKSPACE/tasks/task_*/; do
        if [ -d "$task_dir" ]; then
            task_id=$(basename "$task_dir")
            status=$(cat "$task_dir/status.txt" 2>/dev/null)
            iteration=$(cat "$task_dir/iteration" 2>/dev/null)
            
            case $status in
                "pending") color=$CYAN; icon="⏳" ;;
                "working") color=$YELLOW; icon="⚙️" ;;
                "review")  color=$PURPLE; icon="📝" ;;
                "bug")     color=$RED; icon="🐛" ;;
                "done")    color=$GREEN; icon="✅" ;;
                "failed")  color=$RED; icon="❌" ;;
                *)         color=$NC; icon="❓" ;;
            esac
            
            echo -e "${color}${icon} $task_id [${status}] итерация $iteration${NC}"
            
            # Показываем причину бага если есть
            if [ "$status" == "bug" ] && [ -f "$task_dir/review.txt" ]; then
                local bug_cause=$(head -n1 "$task_dir/review.txt" | cut -c1-80)
                echo -e "  ${RED}└─ Причина: $bug_cause${NC}"
            fi
        fi
    done
}

# Показать логи
show_logs() {
    local agent=$1
    local lines=${2:-20}
    
    echo -e "\n${BLUE}=== ЛОГИ ${agent:-всех} ===${NC}"
    
    if [ -n "$agent" ]; then
        if [ -f "$WORKSPACE/logs/${agent}.log" ]; then
            tail -n "$lines" "$WORKSPACE/logs/${agent}.log"
        else
            echo -e "${RED}Лог для $agent не найден${NC}"
        fi
    else
        for logfile in "$WORKSPACE/logs"/*.log; do
            if [ -f "$logfile" ]; then
                echo -e "\n${GREEN}--- $(basename $logfile) ---${NC}"
                tail -n "$lines" "$logfile"
            fi
        done
    fi
}

# Интерактивное меню
interactive_menu() {
    while $RUNNING; do
        clear
        echo -e "${GREEN}════════════════════════════════════════${NC}"
        echo -e "${GREEN}    AI ОРКЕСТРАТОР (Codex + Qwen)${NC}"
        echo -e "${GREEN}════════════════════════════════════════${NC}"
        
        show_stats
        show_tasks
        
        echo -e "\n${BLUE}=== КОМАНДЫ ===${NC}"
        echo -e "  ${GREEN}[n]${NC} - Новая задача"
        echo -e "  ${GREEN}[l]${NC} - Показать логи (последние 20 строк)"
        echo -e "  ${GREEN}[L]${NC} - Показать логи (последние 50 строк)"
        echo -e "  ${GREEN}[e]${NC} - Логи исполнителя"
        echo -e "  ${GREEN}[r]${NC} - Логи проверяющего"
        echo -e "  ${GREEN}[c]${NC} - Очистить завершённые задачи"
        echo -e "  ${GREEN}[q]${NC} - Выйти"
        
        echo -ne "\n${YELLOW}Выбор: ${NC}"
        read -t 2 cmd
        
        case $cmd in
            n|N)
                echo -ne "${CYAN}Введите задачу для Codex: ${NC}"
                read user_prompt
                if [ -n "$user_prompt" ]; then
                    create_task "$user_prompt"
                    echo -e "${GREEN}✓ Задача создана${NC}"
                    sleep 1
                fi
                ;;
            l|L)
                lines=20
                if [ "$cmd" == "L" ]; then lines=50; fi
                show_logs "" "$lines"
                echo -ne "\n${YELLOW}Нажмите Enter для продолжения...${NC}"
                read
                ;;
            e|E)
                show_logs "executor" 30
                echo -ne "\n${YELLOW}Нажмите Enter для продолжения...${NC}"
                read
                ;;
            r|R)
                show_logs "reviewer" 30
                echo -ne "\n${YELLOW}Нажмите Enter для продолжения...${NC}"
                read
                ;;
            c|C)
                echo -e "${YELLOW}Очистка завершённых задач...${NC}"
                rm -rf "$WORKSPACE/completed"/*
                mkdir -p "$WORKSPACE/completed"
                echo -e "${GREEN}✓ Готово${NC}"
                sleep 1
                ;;
            q|Q)
                echo -e "${YELLOW}Выход...${NC}"
                RUNNING=false
                exit 0
                ;;
        esac
    done
}

# Запуск агентов в отдельных окнах
start_agents() {
    log "$ORCHESTRATOR_NAME" "INFO" "Запуск агентов..."
    
    # Определяем доступный терминал
    local term_cmd=""
    if command -v gnome-terminal &> /dev/null; then
        term_cmd="gnome-terminal --"
    elif command -v konsole &> /dev/null; then
        term_cmd="konsole -e"
    elif command -v xterm &> /dev/null; then
        term_cmd="xterm -e"
    elif command -v tmux &> /dev/null; then
        # Альтернатива - использовать tmux
        tmux new-session -d -s executor './agents/executor.sh'
        tmux new-session -d -s reviewer './agents/reviewer.sh'
        log "$ORCHESTRATOR_NAME" "INFO" "Агенты запущены в tmux"
        return
    else
        log "$ORCHESTRATOR_NAME" "WARNING" "Не найден графический терминал, запуск в фоне"
        ./agents/executor.sh &
        ./agents/reviewer.sh &
        return
    fi
    
    # Запускаем в отдельных окнах
    $term_cmd bash -c "echo '=== ИСПОЛНИТЕЛЬ (Codex) ==='; ./agents/executor.sh; exec bash" &
    sleep 1
    $term_cmd bash -c "echo '=== ПРОВЕРЯЮЩИЙ (Qwen) ==='; ./agents/reviewer.sh; exec bash" &
    
    log "$ORCHESTRATOR_NAME" "INFO" "Агенты запущены в графических окнах"
}

# Проверка наличия CLI моделей
check_dependencies() {
    local missing=0
    
    echo -e "${BLUE}Проверка зависимостей...${NC}"
    
    # Проверка Codex
    if ! command -v $CODEX_CMD &> /dev/null; then
        echo -e "${RED}❌ $CODEX_CMD не найден${NC}"
        missing=1
    else
        echo -e "${GREEN}✅ $CODEX_CMD найден${NC}"
    fi
    
    # Проверка Qwen
    if ! command -v $QWEN_CMD &> /dev/null; then
        echo -e "${RED}❌ $QWEN_CMD не найден${NC}"
        missing=1
    else
        echo -e "${GREEN}✅ $QWEN_CMD найден${NC}"
    fi
    
    if [ $missing -eq 1 ]; then
        echo -e "\n${RED}Ошибка: Не все зависимости установлены${NC}"
        echo "Установите:"
        echo "  - Codex: pip install codex-cli"
        echo "  - Qwen: pip install qwen-cli или используйте ollama"
        exit 1
    fi
}

# Инициализация workspace
init_workspace() {
    mkdir -p "$WORKSPACE"/{tasks,completed,logs}
    chmod 755 "$WORKSPACE"
    log "$ORCHESTRATOR_NAME" "INFO" "Workspace инициализирован: $WORKSPACE"
}

# Главная функция
main() {
    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║     AI ORCHESTRATOR v1.0              ║${NC}"
    echo -e "${GREEN}║     Codex → Qwen Auto-Cycle           ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    echo ""
    
    check_dependencies
    init_workspace
    
    echo -e "${YELLOW}Запуск агентов...${NC}"
    start_agents
    
    sleep 2
    echo -e "${GREEN}✓ Система готова${NC}"
    echo ""
    
    # Запуск интерактивного меню
    interactive_menu
}

# Запуск
main
6. Быстрый запуск
start_all.sh

bash
#!/bin/bash

# Цвета
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}🚀 Запуск AI Оркестратора${NC}"
echo ""

# Проверка прав
if [ ! -x "./orchestrator.sh" ]; then
    echo -e "${YELLOW}Установка прав доступа...${NC}"
    chmod +x orchestrator.sh agents/*.sh
fi

# Проверка конфига
if [ ! -f "./config/agents.conf" ]; then
    echo -e "${RED}❌ config/agents.conf не найден${NC}"
    exit 1
fi

# Запуск
./orchestrator.sh
7. Тестовый скрипт
tests/test_system.sh

bash
#!/bin/bash

# Тестовая задача
create_test_task() {
    cat > "./workspace/tasks/test_task/prompt.txt" << EOF
Напиши функцию на Python, которая:
1. Принимает список чисел
2. Возвращает отсортированный список
3. Удаляет дубликаты

Функция должна называться sort_unique.
EOF
    
    echo "pending" > "./workspace/tasks/test_task/status.txt"
    echo "0" > "./workspace/tasks/test_task/iteration"
    mkdir -p "./workspace/tasks/test_task/code"
    
    echo "✅ Тестовая задача создана"
}

# Запуск теста
create_test_task
echo "Запустите orchestrator.sh для обработки"
📥 Инструкция по установке
Быстрая установка (5 минут)
bash
# 1. Создайте директорию проекта
mkdir ai-orchestrator && cd ai-orchestrator

# 2. Создайте все файлы по структуре выше
# (скопируйте содержимое каждого файла)

# 3. Установите зависимости
pip install codex-cli qwen-cli

# ИЛИ для Ollama:
# curl -fsSL https://ollama.com/install.sh | sh
# ollama pull qwen:7b

# 4. Настройте конфиг
nano config/agents.conf
# Укажите правильные пути к CLI командам

# 5. Дайте права на выполнение
chmod +x orchestrator.sh agents/*.sh start_all.sh

# 6. Запустите
./start_all.sh
Установка через Git (если есть репозиторий)
bash
git clone <your-repo-url> ai-orchestrator
cd ai-orchestrator
./start_all.sh
🎮 Инструкция по использованию
Базовое использование
Запуск системы:

bash
./start_all.sh
Создание задачи:

Нажмите n в оркестраторе

Введите задачу для Codex

Например: "Напиши парсер JSON на Python"

Мониторинг:

Автоматически видите статус всех задач

Цветовая индикация:

⏳ Ожидание (голубой)

⚙️ Выполнение (жёлтый)

📝 Проверка (фиолетовый)

🐛 Баг (красный)

✅ Готово (зелёный)

Просмотр логов:

l - все логи (20 строк)

L - все логи (50 строк)

e - логи исполнителя

r - логи проверяющего

Продвинутое использование
Создание задачи из файла:

bash
echo "Напиши функцию для валидации email" > task.txt
./orchestrator.sh < task.txt
Пакетный режим:

bash
# Создать 5 задач
for i in {1..5}; do
    echo "Задача $i: напиши hello world" | ./orchestrator.sh
done
Автоматический запуск при старте системы:

bash
# Добавить в crontab
@reboot cd /path/to/ai-orchestrator && ./start_all.sh
🔌 API и интеграция
REST API (опционально)
api_server.py:

python
from flask import Flask, request, jsonify
import subprocess
import json
import os

app = Flask(__name__)
WORK_DIR = "/path/to/ai-orchestrator"

@app.route('/task', methods=['POST'])
def create_task():
    data = request.json
    prompt = data.get('prompt')
    
    if not prompt:
        return jsonify({'error': 'No prompt provided'}), 400
    
    # Создаем задачу через оркестратор
    result = subprocess.run(
        [f'{WORK_DIR}/orchestrator.sh', 'create', prompt],
        cwd=WORK_DIR,
        capture_output=True,
        text=True
    )
    
    return jsonify({
        'task_id': result.stdout.strip(),
        'status': 'created'
    })

@app.route('/status/<task_id>', methods=['GET'])
def get_status(task_id):
    status_file = f'{WORK_DIR}/workspace/tasks/{task_id}/status.txt'
    
    if os.path.exists(status_file):
        with open(status_file, 'r') as f:
            status = f.read().strip()
        return jsonify({'task_id': task_id, 'status': status})
    else:
        return jsonify({'error': 'Task not found'}), 404

@app.route('/result/<task_id>', methods=['GET'])
def get_result(task_id):
    result_file = f'{WORK_DIR}/workspace/tasks/{task_id}/code/output.txt'
    
    if os.path.exists(result_file):
        with open(result_file, 'r') as f:
            result = f.read()
        return jsonify({'task_id': task_id, 'result': result})
    else:
        return jsonify({'error': 'Result not found'}), 404

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
Использование API:

bash
# Создать задачу
curl -X POST http://localhost:5000/task \
  -H "Content-Type: application/json" \
  -d '{"prompt": "Напиши функцию факториала"}'

# Проверить статус
curl http://localhost:5000/status/task_12345678

# Получить результат
curl http://localhost:5000/result/task_12345678
Telegram бот
telegram_bot.py:

python
from telegram import Update
from telegram.ext import Application, CommandHandler, ContextTypes
import subprocess

TOKEN = "YOUR_BOT_TOKEN"
WORK_DIR = "/path/to/ai-orchestrator"

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    await update.message.reply_text(
        "🤖 AI Оркестратор бот\n"
        "Используй /task <описание> для создания задачи\n"
        "Используй /status <task_id> для проверки статуса"
    )

async def create_task(update: Update, context: ContextTypes.DEFAULT_TYPE):
    prompt = ' '.join(context.args)
    if not prompt:
        await update.message.reply_text("❌ Укажите задачу")
        return
    
    result = subprocess.run(
        [f'{WORK_DIR}/orchestrator.sh', 'create', prompt],
        cwd=WORK_DIR,
        capture_output=True,
        text=True
    )
    
    task_id = result.stdout.strip()
    await update.message.reply_text(f"✅ Задача создана: {task_id}")

app = Application.builder().token(TOKEN).build()
app.add_handler(CommandHandler("start", start))
app.add_handler(CommandHandler("task", create_task))
app.run_polling()
🔍 Отладка и мониторинг
Просмотр состояния
bash
# Статистика по всем задачам
./tools/stats.sh

# Просмотр конкретной задачи
cat workspace/tasks/task_*/status.txt

# Мониторинг в реальном времени
watch -n 1 'ls -la workspace/tasks/*/status.txt'
Логи
bash
# Все логи
tail -f workspace/logs/*.log

# Только ошибки
grep ERROR workspace/logs/*.log

# Логи за последний час
find workspace/logs -name "*.log" -mmin -60 -exec cat {} \;
Очистка
bash
# Очистить workspace
./tools/cleanup.sh

# Сделать бэкап
./tools/backup.sh

# Удалить старые задачи (старше 7 дней)
find workspace/completed -type d -mtime +7 -exec rm -rf {} \;
Типичные проблемы и решения
Проблема	Решение
Codex не отвечает	Проверьте codex --help, переустановите pip install --upgrade codex-cli
Qwen не отвечает	Проверьте интернет, используйте ollama run qwen для локальной версии
Зависла задача	Вручную установите статус: echo "pending" > workspace/tasks/task_XXX/status.txt
Permission denied	chmod +x *.sh agents/*.sh
Нет логов	Проверьте права на запись: chmod 755 workspace/logs
🚀 Расширение системы
Добавление нового агента (например, тестировщик)
Создайте agents/tester.sh:

bash
#!/bin/bash
source "$(dirname "$0")/common.sh"

while true; do
    task_dir=$(get_task_by_status "test")
    if [ -n "$task_dir" ]; then
        # Логика тестирования
        update_status "$task_dir" "testing"
        # ... выполнить тесты ...
        if tests_passed; then
            update_status "$task_dir" "done"
        else
            update_status "$task_dir" "bug"
        fi
    fi
    sleep 2
done
Обновите машину состояний в common.sh

Добавьте запуск в orchestrator.sh

Параллельное выполнение
Увеличьте MAX_PARALLEL_TASKS в конфиге до 5 или 10.

Docker контейнеризация
Dockerfile:

dockerfile
FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    bash curl python3-pip

RUN pip3 install codex-cli qwen-cli

WORKDIR /app
COPY . .

RUN chmod +x orchestrator.sh agents/*.sh

CMD ["./orchestrator.sh"]
Запуск:

bash
docker build -t ai-orchestrator .
docker run -it ai-orchestrator
📊 Производительность
Ожидаемые показатели
Время выполнения задачи: 10-60 секунд (зависит от сложности)

Циклы исправления: в среднем 1-2 итерации

Пропускная способность: до 100 задач в час

Потребление памяти: ~500MB на агента

Оптимизация
Кеширование промптов - уменьшает время вызова моделей

Балансировка нагрузки - распределение задач между агентами

Асинхронная обработка - не блокирующий ввод-вывод

📝 Лицензия
MIT License

Copyright (c) 2026 AI Orchestrator

Разрешается использование, копирование, модификация, слияние, публикация, распространение, сублицензирование и/или продажа копий программного обеспечения.

🤝 Поддержка
При возникновении проблем:

Проверьте раздел отладки

Просмотрите логи: tail -100 workspace/logs/executor.log

Создайте issue в репозитории проекта

Версия документа: 1.0
Готов к разработке: ✅
Оценка времени разработки: 4-6 часов
Приоритет: Высокий




