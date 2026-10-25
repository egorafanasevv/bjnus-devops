# Bonus HW — url-probe

## Запуск

```bash
docker compose up -d --build
```

Стек: url-probe, Node Exporter, Prometheus и тестовый Nginx.

Prometheus доступен на `http://localhost:9090`.

## Решения

### Образ

Использовал `python:3.11-alpine`, так как скрипту не нужны внешние библиотеки. `su-exec` запускает Python от пользователя `app`, а cron работает от root.

Список URL подключается через volume, таймаут задаётся переменной окружения. Пересобирать образ при их изменении не нужно.

### Расписание

Использовал обычный BusyBox `crond` с расписанием `* * * * *`. Переменные сохраняются при старте контейнера, а вывод перенаправляется в `docker logs`.

### Мониторинг

Скрипт записывает `url_probe.prom` в общий Docker volume. Node Exporter читает файл через textfile collector, а Prometheus получает метрики от Node Exporter.

### Алерт

Правило `probe_success == 0` с `for: 1m` определяет недоступные URL. Для проверки использовал Nginx, который можно останавливать и запускать через Compose.

## Ответы на вопросы

**1. Почему textfile collector подходит для url-probe, а audit-svc лучше отдавать свой /metrics?**

url-probe запускается раз в минуту и завершается, поэтому ему удобно записывать метрики в файл. Постоянно работающий сервис вроде audit-svc может сам отдавать актуальные метрики по HTTP, включая счётчики запросов и ошибок.

**2. Что будет, если cron перестанет запускать проверки?**

`probe_success` сохранит последнее значение, а `up` останется равным 1, потому что Node Exporter продолжает работать. Обнаружить проблему можно по устаревшему времени последней проверки:

```promql
time() - probe_last_run_timestamp_seconds > 180
```

## Проверки

### 1.1. Запуск не от root

Команда: `docker compose exec -T url-probe su-exec app id`

```text
uid=100(app) gid=101(app) groups=101(app),101(app)

```

### 1.2. Размер образа

Команда: `docker image ls url-probe:bonus`

```text
IMAGE             ID             DISK USAGE   CONTENT SIZE   EXTRA
url-probe:bonus   04b6ead74039       54.7MB             0B   U    

```

### 1.3, 2.3. Изменение таймаута

Команда: `docker compose up -d --no-deps --force-recreate url-probe; проверка docker compose logs`

```text
=== До изменения ===
url-probe-1  | FAIL   0  1.002s http://10.255.255.1
=== После изменения ===
url-probe-1  | FAIL   0  3.003s http://10.255.255.1

```

### 2.1. Расписание cron

Команда: `docker compose exec -T url-probe cat /etc/crontabs/root`

```text
* * * * * /app/run.sh >> /proc/1/fd/1 2>&1

```

### 2.1. Запуск каждую минуту

Команда: `docker compose logs --timestamps url-probe | grep http://test-site | tail -5`

```text
url-probe-1  | 2026-10-25T13:43:02.856758089Z OK   200  0.003s http://test-site
url-probe-1  | 2026-10-25T13:44:02.708619027Z OK   200  0.001s http://test-site
url-probe-1  | 2026-10-25T13:45:02.695216513Z OK   200  0.002s http://test-site
url-probe-1  | 2026-10-25T13:46:02.746276266Z OK   200  0.001s http://test-site
url-probe-1  | 2026-10-25T13:47:02.690886699Z OK   200  0.002s http://test-site

```

### 2.2. Вывод в docker logs

Команда: `docker compose logs --tail=50 url-probe`

```text
url-probe-1  | OK   200  0.264s https://example.com
url-probe-1  | FAIL 404  0.235s https://example.com/no-such-page
url-probe-1  | http://no-such-host.invalid: <urlopen error [Errno -2] Name does not resolve>
url-probe-1  | FAIL   0  0.002s http://no-such-host.invalid
url-probe-1  | http://10.255.255.1: <urlopen error timed out>
url-probe-1  | FAIL   0  1.001s http://10.255.255.1
url-probe-1  | OK   200  0.003s http://test-site
url-probe-1  | OK   200  0.251s https://example.com
url-probe-1  | FAIL 404  0.234s https://example.com/no-such-page
url-probe-1  | http://no-such-host.invalid: <urlopen error [Errno -2] Name does not resolve>
url-probe-1  | FAIL   0  0.002s http://no-such-host.invalid
url-probe-1  | http://10.255.255.1: <urlopen error timed out>
url-probe-1  | FAIL   0  1.002s http://10.255.255.1
url-probe-1  | OK   200  0.001s http://test-site

```

### 1.3, 2.4. Изменение URL без рестарта

Команда: `echo http://test-site/check-url-list >> url-probe/urls.txt; проверка docker compose logs и docker inspect StartedAt`

```text
=== StartedAt до ===
2026-10-25T13:48:14.432877991Z
=== Новый URL ===
url-probe-1  | 2026-10-25T13:51:04.513292690Z FAIL 404  0.001s http://test-site/check-url-list
StartedAt не изменился
=== StartedAt после ===
2026-10-25T13:48:14.432877991Z

```

### 2.5. Автоматический рестарт

Команда: `kill -9 PID главного процесса; проверка docker inspect StartedAt и RestartCount`

```text
=== До ===
Status=running StartedAt=2026-10-25T13:58:46.785686509Z RestartCount=0
=== Аварийное завершение PID=80675 ===
=== После ===
Status=running StartedAt=2026-10-25T13:59:18.387215811Z RestartCount=1

```

### 3.1. Метрики в Prometheus

Команда: `docker compose ps; curl -G --data-urlencode query=probe_success http://localhost:9090/api/v1/query`

```text
=== Контейнеры ===
NAME                       IMAGE                       COMMAND                  SERVICE         CREATED          STATUS          PORTS
bonus_hw-node-exporter-1   prom/node-exporter:v1.9.1   "/bin/node_exporter …"   node-exporter   41 minutes ago   Up 41 minutes   9100/tcp
bonus_hw-prometheus-1      prom/prometheus:v3.5.0      "/bin/prometheus --c…"   prometheus      41 minutes ago   Up 41 minutes   127.0.0.1:9090->9090/tcp
bonus_hw-test-site-1       nginx:alpine                "/docker-entrypoint.…"   test-site       41 minutes ago   Up 20 minutes   80/tcp
bonus_hw-url-probe-1       url-probe:bonus             "/app/entrypoint.sh"     url-probe       36 minutes ago   Up 25 minutes   
=== Метрики ===
{
    "status": "success",
    "data": {
        "resultType": "vector",
        "result": [
            {
                "metric": {
                    "__name__": "probe_success",
                    "instance": "node-exporter:9100",
                    "job": "node",
                    "url": "http://10.255.255.1"
                },
                "value": [
                    1792938260.467,
                    "0"
                ]
            },
            {
                "metric": {
                    "__name__": "probe_success",
                    "instance": "node-exporter:9100",
                    "job": "node",
                    "url": "http://no-such-host.invalid"
                },
                "value": [
                    1792938260.467,
                    "0"
                ]
            },
            {
                "metric": {
                    "__name__": "probe_success",
                    "instance": "node-exporter:9100",
                    "job": "node",
                    "url": "http://test-site"
                },
                "value": [
                    1792938260.467,
                    "1"
                ]
            },
            {
                "metric": {
                    "__name__": "probe_success",
                    "instance": "node-exporter:9100",
                    "job": "node",
                    "url": "https://example.com"
                },
                "value": [
                    1792938260.467,
                    "1"
                ]
            },
            {
                "metric": {
                    "__name__": "probe_success",
                    "instance": "node-exporter:9100",
                    "job": "node",
                    "url": "https://example.com/no-such-page"
                },
                "value": [
                    1792938260.467,
                    "0"
                ]
            }
        ]
    }
}

```

### 3.2. Алерт pending

Команда: `Prometheus API: ALERTS{alertname="UrlProbeDown",url="http://test-site"}`

```text
{
    "status": "success",
    "data": {
        "resultType": "vector",
        "result": [
            {
                "metric": {
                    "__name__": "ALERTS",
                    "alertname": "UrlProbeDown",
                    "alertstate": "pending",
                    "instance": "node-exporter:9100",
                    "job": "node",
                    "url": "http://test-site"
                },
                "value": [
                    1792936823.772,
                    "1"
                ]
            }
        ]
    }
}

```

### 3.2. Алерт firing

Команда: `Prometheus API: ALERTS{alertname="UrlProbeDown",url="http://test-site"}`

```text
{
    "status": "success",
    "data": {
        "resultType": "vector",
        "result": [
            {
                "metric": {
                    "__name__": "ALERTS",
                    "alertname": "UrlProbeDown",
                    "alertstate": "firing",
                    "instance": "node-exporter:9100",
                    "job": "node",
                    "url": "http://test-site"
                },
                "value": [
                    1792936921.02,
                    "1"
                ]
            }
        ]
    }
}

```

### 3.2. Алерт после восстановления

Команда: `Prometheus API: ALERTS{alertname="UrlProbeDown",url="http://test-site"}`

```text
{
    "status": "success",
    "data": {
        "resultType": "vector",
        "result": []
    }
}

```

### 3.2. Проверка правил

Команда: `docker run --rm -v "$PWD/prometheus:/etc/prometheus:ro" --entrypoint promtool prom/prometheus:v3.5.0 check rules /etc/prometheus/rules.yml`

```text
Checking /etc/prometheus/rules.yml
  SUCCESS: 1 rules found


```

## Скриншот

`screenshots/alert-firing.png` — алерт в состоянии Firing.

