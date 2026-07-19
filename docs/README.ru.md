# smtp-egress-audit

`smtp-egress-audit` — безопасный Bash-инструмент только для чтения, предназначенный для расследования жалоб провайдера на аномальное число исходящих SMTP-соединений. Он сопоставляет исходящие TCP SYN, активные сокеты и процессы/PID, события доставки Postfix, SMTP-аутентификацию, входы SSH/IMAP/POP3, очереди, службы, задания cron, systemd timers и контейнеры.

Версия **1.1.0**, лицензия MIT. Инструмент не меняет firewall, Postfix, SSH и Fail2ban, не блокирует IP и не записывает payload пакетов или тела писем.

## Поддерживаемые системы и требования

- Ubuntu 22.04/24.04 и Debian;
- Postfix, включая Mail-in-a-Box;
- Bash 4.4+ и стандартные GNU-утилиты;
- root рекомендуется для чтения всех журналов, `tcpdump`, process/PID, conntrack и systemd;
- основные команды: `awk`, `sed`, `grep`, `sort`, `ss`, `journalctl`;
- необязательные: `tcpdump`, `tcpconnect-bpfcc`, `conntrack`, `postqueue`, `postconf`, `fail2ban-client`, Docker, Podman, `getent`, `timeout`.

Отсутствующая необязательная утилита выводится как `not installed`/`unavailable` и не останавливает аудит. Пакеты автоматически не устанавливаются.

## Установка

```bash
git clone https://github.com/Anton-Babaskin/smtp-egress-audit.git
cd smtp-egress-audit
sudo ./install.sh
```

Скрипт устанавливается в `/usr/local/sbin`, конфигурация — в `/etc/default/smtp-egress-audit`, systemd units — в `/etc/systemd/system`, logrotate — в `/etc/logrotate.d`. Защищённый каталог `/var/log/smtp-egress-audit` создаётся с правами `0700`. Существующая конфигурация сохраняется; заменить её можно только через `--force-config`.

Непрерывный мониторинг сам не запускается. Явное включение при установке:

```bash
sudo ./install.sh --enable-monitor
```

## Использование

```bash
sudo smtp-egress-audit audit
sudo smtp-egress-audit report
sudo smtp-egress-audit watch 3600
sudo smtp-egress-audit monitor
sudo SINCE="7 days ago" smtp-egress-audit report
sudo SMTP_PORT=587 smtp-egress-audit watch 600
```

- `audit` — полный разовый аудит системы и исторических журналов;
- `report` — отчёт по Postfix и входам за `SINCE`;
- `watch [seconds]` — ограниченное наблюдение, по умолчанию 600 секунд;
- `monitor` — наблюдение до SIGTERM или Ctrl+C.

Каждый запуск получает отдельный приватный каталог с UTC timestamp. Общий результат находится в `report.txt`.

## Настройки

```text
LOG_ROOT=/var/log/smtp-egress-audit
SMTP_PORT=25
SINCE="24 hours ago"
SAMPLE_INTERVAL=1
ACTIVE_THRESHOLD=10
INTERFACE=auto
RESOLVE_HOSTNAMES=1
```

`SMTP_PORT` допускает 1–65535: прямой SMTP `25`, SMTPS `465`, Submission `587` и альтернативный relay `2525`. `INTERFACE=auto` выбирает интерфейс default route; разрешено `INTERFACE=any`. PTR lookup имеет короткий timeout и отключается через `RESOLVE_HOSTNAMES=0`.

## Как работает сетевой мониторинг

Используется точный BPF-фильтр:

```text
tcp dst port PORT and (tcp[tcpflags] & tcp-syn != 0)
```

При поддержке включается `tcpdump -Q out`. Сохраняются только декодированные заголовочные метаданные: нет `-X`, `-A`, PCAP, payload и содержимого письма. Снимки `ss -Htanp` позволяют увидеть процесс и PID. При наличии `tcpconnect-bpfcc` он используется как дополнительный источник атрибуции. Итог содержит число SYN, назначения IP:port и замеченные процессы. Превышение `ACTIVE_THRESHOLD` создаёт предупреждение.

```bash
# Прямая доставка на MX по TCP/25
sudo SMTP_PORT=25 smtp-egress-audit watch 3600

# Внешний relay
sudo SMTP_PORT=587 smtp-egress-audit watch 600
sudo SMTP_PORT=2525 smtp-egress-audit watch 600
```

Relay на 587/2525 может работать нормально, в то время как жалоба провайдера относится именно к прямым подключениям на TCP/25. Эти порты проверяются отдельными запусками.

## Расшифровка Postfix

- `NOQUEUE: reject` и `Relay access denied` обычно означают отклонённую входящую попытку до принятия письма в очередь. Это не доказательство успешной исходящей рассылки.
- `postfix/smtp ... status=sent` подтверждает завершённую исходящую доставку, принятую следующим сервером.
- `status=deferred` — временная ошибка и повторная попытка; `status=bounced` — постоянная ошибка.
- `sasl_username` показывает, какая почтовая учётная запись аутентифицировалась. Её нужно сопоставлять со временем, IP клиента, queue ID и доменами получателей.
- `relay=` в строке исходящей доставки показывает фактический следующий узел.

В `postconf -n` password maps и похожие значения заменяются на `configured` или `[REDACTED]`. `/etc/postfix/sasl_passwd` инструмент не читает.

## Mail-in-a-Box

Mail-in-a-Box использует Postfix и Dovecot, поэтому отчёт применяется без специальных изменений. Запустите `audit` от root и сопоставьте:

1. точное время, timezone и порт из жалобы провайдера;
2. направления SYN и процесс/PID из `ss`;
3. queue ID, `postfix/smtp` и `status=`;
4. `sasl_username`, hostname/IP SMTP-клиента и входы Dovecot;
5. очередь, неизвестные процессы, контейнеры, cron и timers.

Этот инструмент не должен изменять сгенерированную MIAB конфигурацию. Сначала сохраните доказательства, затем исправляйте проблему штатными средствами Mail-in-a-Box.

## Linux, SSH и почтовые входы

`audit` показывает `who`, `w`, `last`, `lastlog`, активные SSH-соединения, эффективные `sshd -T` параметры (`port`, `PermitRootLogin`, `PasswordAuthentication`), успешные входы с методом/user/IP, неудачные IP, sudo/su и Fail2ban jail `sshd`. Для Dovecot и SMTP Submission показываются успешные пользователи, IP/hostname, группировки и последние ошибки. PTR успешных IP — необязательная подсказка, а не доказательство личности.

## Системная информация

Полный аудит включает hostname/FQDN, дату, timezone, uptime, reboot history, IP и маршруты, нужные службы, очередь Postfix, cron/timers, Docker/Podman, conntrack для выбранного порта, а также процессы Postfix/Exim/Sendmail.

## systemd

```bash
# Ежедневный отчёт
sudo systemctl enable --now smtp-egress-audit-report.timer

# Непрерывный монитор — только явное включение
sudo systemctl enable --now smtp-egress-audit-monitor.service
sudo systemctl status smtp-egress-audit-monitor.service

# Корректная остановка
sudo systemctl disable --now smtp-egress-audit-monitor.service
```

SIGINT/SIGTERM завершает фоновые процессы захвата и формирует итог.

## Действия после жалобы провайдера

1. Зафиксируйте source IP сервера, порт назначения, число подключений, timezone и точный период.
2. Сразу запустите `sudo smtp-egress-audit audit`, пока не исчезло текущее состояние.
3. Запустите `watch` на указанном провайдером порту.
4. Сравните число SYN с данными провайдера; повторные попытки означают, что подключения не равны количеству писем.
5. Определите владельца сокетов: Postfix, web-приложение, контейнер, другой MTA или неизвестный процесс.
6. Сопоставьте queue ID, `status=sent`, домены получателей, relay и SMTP-пользователей.
7. Отделите отклонённые входящие relay-пробы от реально принятых и отправленных сообщений.
8. Проверьте SSH, Dovecot, SMTP auth, sudo/su, cron/timers, контейнеры и Fail2ban.
9. Сохраните приватный отчёт до исправлений; подтверждённо скомпрометированные учётные записи и workloads обрабатывайте по вашей процедуре incident response.

Подробно: [provider-alert-runbook.md](provider-alert-runbook.md).

## Ограничения

- После перезагрузки исчезают активные сокеты, процессы и часть счётчиков. Поэтому важны исторические логи и точные данные провайдера.
- Ротация журналов и retention journald могут удалить старые события; fallback на файл не умеет идеально фильтровать произвольный `SINCE`.
- NAT, namespaces, короткоживущие процессы и внешний relay могут ограничить атрибуцию.
- Инструмент помогает собирать доказательства, но не заменяет malware-анализ и incident response.

## Проверка и удаление

```bash
make check
sudo ./uninstall.sh
```

Отчёты остаются на месте. Их удаление требует отдельного явного параметра:

```bash
sudo ./uninstall.sh --purge-logs
```
