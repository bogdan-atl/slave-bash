#!/bin/bash

# Подключение файла конфигурации

source ./slave-start.config

# Функция для выполнения команд на удаленном сервере
remote_exec() {
  if [ -z "$REMOTE_PASS" ]; then
    ssh -o StrictHostKeyChecking=no $REMOTE_USER@$REMOTE_HOST "$1"
  else
    sshpass -p "$REMOTE_PASS" ssh -o StrictHostKeyChecking=no $REMOTE_USER@$REMOTE_HOST "$1"
  fi
}


# Проверка переменных
echo "Проверка переменных..."
errors=false

if [ -z "$REMOTE_USER" ]; then
  echo -e "${RED}Ошибка: REMOTE_USER не задан${NC}"
  errors=true
fi

if [ -z "$REMOTE_HOST" ]; then
  echo -e "${RED}Ошибка: REMOTE_HOST не задан${NC}"
  errors=true
fi

if [ -z "$LOCAL_REPLICATION_DIR" ]; then
  echo -e "${RED}Ошибка: LOCAL_REPLICATION_DIR не задан${NC}"
  errors=true
fi

if [ -z "$MYSQL_USER" ]; then
  echo -e "${RED}Ошибка: MYSQL_USER не задан${NC}"
  errors=true
fi

if [ -z "$MASTER_HOST" ]; then
  echo -e "${RED}Ошибка: MASTER_HOST не задан${NC}"
  errors=true
fi

if [ -z "$CHANGE_MASTER_USER" ]; then
  echo -e "${RED}Ошибка: CHANGE_MASTER_USER не задан${NC}"
  errors=true
fi

if [ -z "$CHANGE_MASTER_PASS" ]; then
  echo -e "${RED}Ошибка: CHANGE_MASTER_PASS не задан${NC}"
  errors=true
fi

if [ -z "$MARIABACKUP_CMD" ]; then
  echo -e "${RED}Ошибка: MARIABACKUP_CMD не задан${NC}"
  errors=true
fi

if [ -z "$MYSQL_SERVICE" ]; then
  echo -e "${RED}Ошибка: MYSQL_SERVICE не задан${NC}"
  errors=true
fi

# Проверка подключения по SSH
echo "Проверка подключения по SSH..."
if remote_exec "echo Подключение успешно"; then
  echo -e "${GREEN}Подключение по SSH успешно${NC}"
else
  echo -e "${RED}Ошибка подключения по SSH${NC}"
  errors=true
fi

# Проверка подключения к MySQL
echo "Проверка подключения к MySQL..."
if MYSQL_PWD=$MYSQL_PASS mysql -u $MYSQL_USER -e "SELECT 1"; then
  echo -e "${GREEN}Подключение к MySQL успешно${NC}"
else
  echo -e "${RED}Ошибка подключения к MySQL${NC}"
  errors=true
fi

# Проверка подключения к MySQL на удаленном сервере
echo "Проверка подключения к MySQL на удаленном сервере..."
if remote_exec "MYSQL_PWD=$MYSQL_PASS mysql -u $MYSQL_USER -e 'SELECT 1'"; then
  echo -e "${GREEN}Подключение к MySQL на удаленном сервере успешно${NC}"
else
  echo -e "${RED}Ошибка подключения к MySQL на удаленном сервере${NC}"
  errors=true
fi

# Проверка наличия локальной директории
echo "Проверка наличия локальной директории..."
if [ -d "$LOCAL_REPLICATION_DIR" ]; then
  echo -e "${GREEN}Локальная директория существует${NC}"
else
  echo -e "${RED}Локальная директория не существует, создаем...${NC}"
  mkdir -p $LOCAL_REPLICATION_DIR
  if [ $? -ne 0 ]; then
    echo -e "${RED}Ошибка создания локальной директории${NC}"
    errors=true
  fi
fi

# Проверка наличия удаленной директории
echo "Проверка наличия удаленной директории..."
if remote_exec "[ -d $REMOTE_MYSQL_DIR ]"; then
  echo -e "${GREEN}Удаленная директория существует${NC}"
else
  echo -e "${RED}Удаленная директория не существует, создаем...${NC}"
  remote_exec "mkdir -p $REMOTE_MYSQL_DIR"
  if [ $? -ne 0 ]; then
    echo -e "${RED}Ошибка создания удаленной директории${NC}"
    errors=true
  fi
fi

# Проверка наличия сервиса MySQL/MariaDB
echo "Проверка наличия сервиса $MYSQL_SERVICE..."
if remote_exec "systemctl status $MYSQL_SERVICE"; then
  echo -e "${GREEN}Сервис $MYSQL_SERVICE существует${NC}"
else
  echo -e "${RED}Сервис $MYSQL_SERVICE не найден${NC}"
  errors=true
fi

# Проверка наличия утилиты для бэкапа
echo "Проверка наличия утилиты для бэкапа $MARIABACKUP_CMD..."
if command -v $MARIABACKUP_CMD >/dev/null 2>&1; then
  echo -e "${GREEN}Утилита $MARIABACKUP_CMD существует${NC}"
else
  echo -e "${RED}Утилита $MARIABACKUP_CMD не найдена${NC}"
  errors=true
fi

# Проверка наличия утилиты sshpass (если используется пароль)
if [ ! -z "$REMOTE_PASS" ]; then
  echo "Проверка наличия утилиты sshpass..."
  if command -v sshpass >/dev/null 2>&1; then
    echo -e "${GREEN}Утилита sshpass существует${NC}"
  else
    echo -e "${RED}Утилита sshpass не найдена${NC}"
    errors=true
  fi
fi

# Если есть ошибки, завершить скрипт
if $errors; then
  echo -e "${RED}Обнаружены ошибки. Завершение скрипта.${NC}"
  exit 1
fi

# Подтверждение выполнения
read -p "Все проверки прошли успешно. Продолжить выполнение скрипта? (y/n): " confirm
if [ "$confirm" != "y" ]; then
  echo "Скрипт прерван пользователем."
  exit 1
fi

# Основной функционал скрипта...
echo -e "${GREEN}Все проверки успешно пройдены. Начинаем выполнение основного функционала.${NC}"

# Шаг 1: Остановить MariaDB/MySQL на удаленном сервере
remote_exec "systemctl stop $MYSQL_SERVICE"

# Шаг 2: Удалить все в папке /mnt/ssd/mysql/ на удаленном сервере
remote_exec "rm -rf ${REMOTE_MYSQL_DIR}*"

# Шаг 3: Выполнить бекап на локальном сервере
ionice -c3 $MARIABACKUP_CMD --backup --target-dir=$LOCAL_REPLICATION_DIR --user=$MYSQL_USER --password=$MYSQL_PASS

# Шаг 4: Подготовить копию на локальном сервере
ionice -c3 $MARIABACKUP_CMD --prepare --target-dir=$LOCAL_REPLICATION_DIR

# Шаг 5: Перебросить файлы на конечный сервер
if [ -z "$REMOTE_PASS" ]; then
  rsync -avz -e ssh ${LOCAL_REPLICATION_DIR}/* ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_MYSQL_DIR}
else
  sshpass -p "$REMOTE_PASS" rsync -avz -e ssh ${LOCAL_REPLICATION_DIR}/* ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_MYSQL_DIR}
fi

# Проверка успешности rsync
if [ $? -eq 0 ]; then
  echo "Файлы успешно переданы на конечный сервер."
  # Удаление файлов из локальной папки
  rm -rf ${LOCAL_REPLICATION_DIR}/*
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}Локальные файлы успешно удалены.${NC}"
  else
    echo -e "${RED}Ошибка при удалении локальных файлов.${NC}"
  fi
else
  echo -e "${RED}Ошибка при передаче файлов на конечный сервер.${NC}"
fi

# Шаг 6: Сменить владельца файлов на mysql
remote_exec "chown -R mysql:mysql ${REMOTE_MYSQL_DIR}"

# Шаг 7: Запустить MariaDB/MySQL на удаленном сервере
remote_exec "systemctl start $MYSQL_SERVICE"

# Шаг 8: Настроика slave-сервера
remote_exec "
echo 'Stopping slave...'
MYSQL_PWD=$MYSQL_PASS mysql -u $MYSQL_USER -e 'STOP SLAVE;'
echo 'Reset slave...'
MYSQL_PWD=$MYSQL_PASS mysql -u $MYSQL_USER -e 'RESET SLAVE;'

# Получаем MASTER_LOG_FILE и MASTER_LOG_POS из файла xtrabackup_binlog_info
MASTER_LOG_FILE=\$(cat ${REMOTE_MYSQL_DIR}/xtrabackup_binlog_info | awk '{print \$1}')
MASTER_LOG_POS=\$(cat ${REMOTE_MYSQL_DIR}/xtrabackup_binlog_info | awk '{print \$2}')

echo 'Changing master and starting slave...'
MYSQL_PWD=$MYSQL_PASS mysql -u $MYSQL_USER -e \"CHANGE MASTER TO MASTER_HOST='$MASTER_HOST', MASTER_USER='$CHANGE_MASTER_USER', MASTER_PASSWORD='$CHANGE_MASTER_PASS', MASTER_LOG_FILE='\$MASTER_LOG_FILE', MASTER_LOG_POS=\$MASTER_LOG_POS;\"
MYSQL_PWD=$MYSQL_PASS mysql -u $MYSQL_USER -e 'START SLAVE;'

# Wait until Seconds_Behind_Master is 0
while true; do
    SECONDS_BEHIND_MASTER=\$(MYSQL_PWD=$MYSQL_PASS mysql -u $MYSQL_USER -e 'SHOW SLAVE STATUS\\G' | grep 'Seconds_Behind_Master' | awk '{print \$2}')
    LAST_IO_ERROR=\$(MYSQL_PWD=$MYSQL_PASS mysql -u $MYSQL_USER -e 'SHOW SLAVE STATUS\\G' | grep 'Last_IO_Error' | cut -d: -f2-)
    LAST_SQL_ERROR=\$(MYSQL_PWD=$MYSQL_PASS mysql -u $MYSQL_USER -e 'SHOW SLAVE STATUS\\G' | grep 'Last_SQL_Error' | cut -d: -f2-)
    if [ \"\$SECONDS_BEHIND_MASTER\" -eq 0 ]; then
        break
    fi
    if [ -n \"\$LAST_IO_ERROR\" ] || [ -n \"\$LAST_SQL_ERROR\" ]; then
        echo -e \"${RED}Ошибка: \$LAST_IO_ERROR \$LAST_SQL_ERROR${NC}\"
        exit 1
    fi
    sleep 5
done

echo 'Stopping slave...'
MYSQL_PWD=$MYSQL_PASS mysql -u $MYSQL_USER -e 'STOP SLAVE;'

echo 'Changing master to use GTID and starting slave...'
MYSQL_PWD=$MYSQL_PASS mysql -u $MYSQL_USER -e \"CHANGE MASTER TO MASTER_HOST='$MASTER_HOST', MASTER_USER='$CHANGE_MASTER_USER', MASTER_PASSWORD='$CHANGE_MASTER_PASS', MASTER_USE_GTID=slave_pos;\"

echo 'Start slave...'
MYSQL_PWD=$MYSQL_PASS mysql -u $MYSQL_USER -e 'START SLAVE;'
"