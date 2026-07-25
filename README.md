# POScenter FR Manager

GUI-утилита для подключения к фискальным регистраторам (ФР) **Poscenter Ритейл 01-ФМ** через SSH-туннель, а также для удаленного управления кассами и настройки пинпадов Сбербанк.

## Зависимости

- Windows 10/11
- PowerShell 5.1+
- [plink.exe](https://www.chiark.greenend.org.uk/~sgtatham/putty/latest.html) (в комплекте)

## Установка на новый компьютер

### 1. Скачайте репозиторий

```
git clone https://github.com/dagmorport/poscenter-fr-manager.git
```

Или скачайте ZIP-архив с GitHub и распакуйте.

### 2. Обязательные файлы

Убедитесь что в папке есть:

```
poscenter/
├── app.ps1              # Главное GUI приложение
├── run.bat              # Быстрый запуск
├── config.json          # Конфигурация (шаблон)
├── plink.exe            # SSH клиент (должен быть в папке)
├── lib/
│   ├── config.ps1       # Чтение конфигурации
│   ├── ssh.ps1          # SSH-хелперы
│   ├── logging.ps1      # Логирование
│   └── update.ps1       # Автообновление
├── update.ps1           # Скрипт обновления
├── connect.ps1          # CLI подключение
└── disconnect.ps1       # Отключение
```

### 3. Скачайте plink.exe

plink.exe не входит в репозиторий. Скачайте с официального сайта:
https://www.chiark.greenend.org.uk/~sgtatham/putty/latest.html

Положите `plink.exe` в корень папки `poscenter/`.

### 4. Создайте конфигурацию

Скопируйте `config.json` в `config.local.json`:

```
copy config.json config.local.json
```

Отредактируйте `config.local.json`:

```json
{
  "fr_ip": "192.168.X.X",
  "fr_port": 7778,
  "local_port": 17778,
  "ssh_port": 22,
  "ssh_user": "root",
  "ssh_password": "ВАШ_ПАРОЛЬ",
  "plink_path": "",
  "kassas": [
    {"name": "KASSA_1", "ip": "192.168.1.100"},
    {"name": "KASSA_2", "ip": "192.168.1.101"}
  ],
  "remote_commands": [...]
}
```

Параметры:
- `ssh_password` — пароль root от касс
- `kassas` — список касс (name + ip)
- `remote_commands` — команды (оставьте как есть)

### 5. Запустите

```
run.bat
```

Или через PowerShell:
```
.\app.ps1
```

## Возможности

### Подключение к ФР
- Выберите кассу из списка
- Нажмите **Connect**
- Нажмите **Copy Address** → вставьте `127.0.0.1:17778` в настройки драйвера ДККТ

### Удаленные команды (Commands)
- Перезагрузка кассы
- Убить/Перезапустить/Статус GUI
- Обновить приложение

### Настройка пинпада Сбербанк (Terminal)
Команды для настройки пинпада Kozen P10 на кассах:

1. **Установить Сбербанк** — `aptitude install -y artix-sb`
2. **Настроить пинпад** — создает udev правило для symlink ttyKozen/ttyS99
3. **Копировать файлы Сбербанк** — копирует sb_pilot, upnixmn.out из files/
4. **Настроить findcom.ini** — настраивает поиск COM-порта для Kozen
5. **Настроить pinpad.ini** — создает конфиг пинпада

Диагностика: Проверить USB, Порты, pinpad.ini, findcom.ini

## CLI

```powershell
# Подключение к конкретной кассе
.\connect.ps1 -IP 192.168.1.100

# Подключение с выбором из списка
.\connect.ps1

# Отключение всех туннелей
.\disconnect.ps1
```

## Структура проекта

| Файл | Описание |
|------|----------|
| `app.ps1` | GUI приложение |
| `connect.ps1` | CLI подключение |
| `disconnect.ps1` | Отключение туннеля |
| `update.ps1` | Автообновление с GitHub |
| `version.txt` | Текущая версия |
| `config.json` | Конфигурация (шаблон) |
| `config.local.json` | Локальная конфигурация (не в git) |
| `run.bat` | Быстрый запуск |
| `lib/` | Модули (config, ssh, logging, update) |

## Лицензия

MIT
