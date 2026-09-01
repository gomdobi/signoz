# GOMDOBI SigNoZ Foundry 배포 메모

이 저장소의 업그레이드와 배포 흐름은 아래 체인으로 본다.

```text
SigNoZ/signoz upstream 릴리즈 태그 -> gomdobi/signoz main
                                      -> 100.203:/app/signoz
                                      -> 100.204:/app/signoz
```

- `100.203`: 내부망 독립 SigNoZ 풀스택 서버
- `100.204`: 외부망 독립 SigNoZ 풀스택 서버

업그레이드 기준은 upstream 정식 릴리즈 태그다. `v0.130.1`부터 upstream의 legacy Docker Compose 파일은 제거되고 Foundry 기준으로 전환되었으므로, 양쪽 서버 모두 `deploy/foundry` 기준으로 배포한다.

## 현재 배포 기준

- 확인일: 2026-09-01
- upstream 릴리즈 태그: `v0.139.0`
- foundryctl: `v0.2.17`
- 100.203/100.204 foundryctl 경로: `/usr/local/bin/foundryctl` (`root:root`, `0755`)
- 100.203/100.204 SigNoZ 이미지: `signoz/signoz:v0.139.0`
- 100.203/100.204 collector 이미지: `signoz/signoz-otel-collector:v0.144.6`
- 100.203/100.204 ClickHouse 이미지: `clickhouse/clickhouse-server:25.12.5`
- 100.203/100.204 ZooKeeper 이미지: `signoz/zookeeper:3.7.1`
- 100.203/100.204 Docker 네트워크: `signoz-network`
- 100.203/100.204 ClickHouse 데이터 경로: `/data/sayit-clickhouse`
- 100.203/100.204 SQLite 데이터 경로: `/data/sayit-sqlite`
- 100.203/100.204 ZooKeeper 데이터 경로: `/data/sayit-zookeeper`
- 100.203/100.204 ClickHouse 컨테이너 mount: `/var/lib/clickhouse`
- ClickHouse bind mount 반영 커밋: `b48ff8e601`
- 서버별 롤백 Compose: `/app/signoz-runtime/compose.clickhouse-volume.rollback.yaml`

2026-09-01 전환 검증에서 양쪽 서버 모두 ClickHouse v25.12.5.44, SigNoZ API `ok`, ClickHouse/SigNoZ health `healthy`, migrator 종료 코드 `0`, 완료되지 않은 mutation `0`을 확인했다. 이후 전체 스택을 정지하고 SQLite와 ZooKeeper 데이터도 `/data`로 이전했으며, 재기동 후 SigNoZ·ZooKeeper·ClickHouse health와 migrator 종료 코드 `0`을 다시 확인했다. 이전 `signoz-clickhouse`, `signoz-sqlite`, `signoz-zookeeper-1` Docker 볼륨은 삭제하지 않고 롤백용으로 보존했다.

## Foundry 파일

- casting: `deploy/foundry/casting.yaml`
- generated compose: `deploy/foundry/pours/deployment/compose.yaml`
- ingester config: `deploy/foundry/pours/deployment/ingester/ingester.yaml`
- ClickHouse config: `deploy/foundry/pours/deployment/telemetrystore/clickhouse/config-0-0.yaml`
- ClickHouse 저장소 운영 절차: `deploy/foundry/CLICKHOUSE_DATA_STORAGE_RUNBOOK.md`

## 반드시 유지할 커스텀

### `deploy/foundry/casting.yaml`

- `metastore.kind`는 `sqlite`를 사용한다.
- `telemetrykeeper.kind`는 기존 데이터 볼륨 재사용을 위해 `zookeeper`를 사용한다.
- ClickHouse macro는 기존 값과 일치해야 한다.
  - `shard: "01"`
  - `replica: "example01-01-1"`
- ClickHouse의 `sayis` 사용자는 `sayis-dashboard-api` 전용 읽기 계정으로 유지한다.
  - 인증 설정: `password`
  - 권한: `GRANT SELECT ON signoz_metrics.*`
  - 권한: `GRANT SELECT ON signoz_traces.*`
  - 원본 암호는 프라이빗 저장소의 casting에 유지한다.
- 영구 데이터는 호스트 bind mount를 사용한다.
  - `/data/sayit-clickhouse:/var/lib/clickhouse`
  - `/data/sayit-sqlite:/var/lib/signoz`
  - `/data/sayit-zookeeper:/bitnami/zookeeper`
  - JSON Patch의 `test`로 Foundry가 생성한 기존 mount를 먼저 검증한 뒤 `replace`한다.
  - upstream 생성 구조가 바뀌어 `test`가 실패하면 patch 경로를 임의로 우회하지 않고 생성물을 비교한다.
- 이전 `signoz-clickhouse`, `signoz-sqlite`, `signoz-zookeeper-1` 볼륨은 롤백용으로 보존하며 Compose에서 관리하지 않는다.
- Docker 네트워크는 Foundry 공식 이름인 `signoz-network`를 사용한다.

### `deploy/foundry/pours/deployment/compose.yaml`

- `signoz-signoz-0.image`는 대상 SigNoZ 버전과 일치해야 한다.
- `ingester.image`와 `signoz-telemetrystore-migrator.image`는 collector 기준 버전과 일치해야 한다.
- ClickHouse 포트는 아래 포트를 노출해야 한다.
  - `9000:9000`
  - `8123:8123`
  - `9181:9181`
- 영구 데이터 mount는 아래 값을 유지해야 한다.
  - `/data/sayit-clickhouse:/var/lib/clickhouse`
  - `/data/sayit-sqlite:/var/lib/signoz`
  - `/data/sayit-zookeeper:/bitnami/zookeeper`
- ingester 포트는 아래 포트를 노출해야 한다.
  - `4317:4317`
  - `4318:4318`
  - `8889:8889`
- ingester volume에는 아래 secret mount가 있어야 한다.
  - `/app/secrets/uptime_kuma_api_key:/app/secrets/uptime_kuma_api_key:ro`
- compose network name은 Foundry 공식 이름인 `signoz-network`여야 한다.
- 서비스 간 통신은 Foundry 공식 서비스명과 공식 alias를 사용한다.

### `deploy/foundry/pours/deployment/ingester/ingester.yaml`

- `receivers.prometheus.config.scrape_configs`에 `job_name: uptime-kuma`가 있어야 한다.
- `uptime-kuma` scrape job은 아래 값을 유지해야 한다.
  - `metrics_path: /metrics`
  - `scrape_interval: 30s`
  - `basic_auth.username: apikey`
  - `basic_auth.password_file: /app/secrets/uptime_kuma_api_key`
  - target `uptime-kuma:3001`
  - label `job_name: uptime-kuma`
- collector self-scrape target은 `0.0.0.0:8888`이어야 한다.
- `exporters.prometheus.endpoint`는 `0.0.0.0:8889`이어야 한다.
- `service.pipelines.metrics.exporters`에 `prometheus`가 있어야 한다.
- `service.pipelines.metrics/prometheus.exporters`에 `prometheus`가 있어야 한다.

## 업그레이드 확인 순서

1. upstream 정식 릴리즈 태그를 먼저 확인한다.

```bash
git fetch upstream --tags
git ls-remote --tags --sort='version:refname' upstream 'refs/tags/v*' | grep -v '\^{}' | tail
```

2. Foundry casting을 생성하고 산출물을 검증한다.

```bash
foundryctl forge --no-updater --no-ledger -f deploy/foundry/casting.yaml -p deploy/foundry/pours
docker compose -f deploy/foundry/pours/deployment/compose.yaml config --quiet
```

`foundryctl forge`가 실패하면 기존 `pours`를 배포하지 않는다. 특히 ClickHouse mount의 JSON Patch `test` 실패는 upstream 생성 구조가 달라졌다는 의미이므로 `casting.yaml`과 새 생성물을 먼저 비교한다.

3. 커스텀 유지 여부를 확인한다.

```bash
grep -nE 'signoz/signoz:v|signoz-otel-collector:v|clickhouse/clickhouse-server:|signoz/zookeeper:|9000:9000|8123:8123|9181:9181|8889:8889|uptime_kuma_api_key|/data/sayit-clickhouse:/var/lib/clickhouse' deploy/foundry/pours/deployment/compose.yaml
grep -nE 'job_name: uptime-kuma|password_file: /app/secrets/uptime_kuma_api_key|endpoint: 0.0.0.0:8889|prometheus' deploy/foundry/pours/deployment/ingester/ingester.yaml
grep -nE 'replica: example01-01-1|shard: "01"|sayis:|GRANT SELECT ON signoz_(metrics|traces)\.\*' deploy/foundry/pours/deployment/telemetrystore/clickhouse/config-0-0.yaml
test "$(grep -Fc '/data/sayit-clickhouse:/var/lib/clickhouse' deploy/foundry/pours/deployment/compose.yaml)" -eq 1
! grep -qE 'signoz-clickhouse|signoz-telemetrystore-0-0-data:/var/lib/clickhouse' deploy/foundry/pours/deployment/compose.yaml
```

4. `sayis-dashboard-api`에 영향을 줄 수 있는 ClickHouse 구조 변경을 확인한다.

- ClickHouse, collector, telemetrystore migrator 이미지 버전을 이전 배포와 비교한다.
- telemetry 테이블의 engine, sorting key, partition key, primary key를 비교한다.
- View와 Materialized View의 생성 SQL을 비교한다.
- 구조 변경이 있으면 API 주요 쿼리의 실행 계획과 응답시간을 배포 전후로 비교한다.

```sql
SELECT
    database,
    name,
    engine,
    sorting_key,
    partition_key,
    primary_key,
    create_table_query
FROM system.tables
WHERE database LIKE 'signoz%'
ORDER BY database, name;
```

## 100.203/100.204 공통 준비

양쪽 서버 모두 `/app/signoz`를 `origin/main`과 일치시킨 뒤 공식 Foundry 산출물을 생성하고 검증한다.

`/data`가 실제 LVM 파일시스템으로 mount되지 않은 상태에서 Compose를 기동하면 안 된다. Docker가 호스트 루트 파일시스템에 같은 경로를 만들 수 있으므로 `findmnt` 결과를 먼저 고정 검증한다.

```bash
cd /app/signoz
test "$(findmnt -n -o TARGET -T /data/sayit-clickhouse)" = "/data"
test "$(findmnt -n -o SOURCE -T /data/sayit-clickhouse)" = "/dev/mapper/vg_data-lv_data"
test "$(findmnt -n -o TARGET -T /data/sayit-sqlite)" = "/data"
test "$(findmnt -n -o TARGET -T /data/sayit-zookeeper)" = "/data"
sudo git pull --ff-only origin main
sudo /usr/local/bin/foundryctl forge --no-updater --no-ledger \
  -f deploy/foundry/casting.yaml \
  -p deploy/foundry/pours
sudo docker compose \
  -f deploy/foundry/pours/deployment/compose.yaml \
  config --quiet
```

## 100.203 내부망 풀스택 배포

```bash
cd /app/signoz
test "$(findmnt -n -o TARGET -T /data/sayit-clickhouse)" = "/data"
test "$(findmnt -n -o TARGET -T /data/sayit-sqlite)" = "/data"
test "$(findmnt -n -o TARGET -T /data/sayit-zookeeper)" = "/data"
sudo docker compose \
  -f deploy/foundry/pours/deployment/compose.yaml \
  pull
sudo docker compose \
  -f deploy/foundry/pours/deployment/compose.yaml \
  up -d
```

## 100.204 외부망 풀스택 배포

100.204의 호스트 전용 설정은 Git 저장소 밖의 `/app/signoz-runtime/docker-compose.204.override.yaml`에서 유지한다.

```bash
cd /app/signoz
test "$(findmnt -n -o TARGET -T /data/sayit-clickhouse)" = "/data"
test "$(findmnt -n -o TARGET -T /data/sayit-sqlite)" = "/data"
test "$(findmnt -n -o TARGET -T /data/sayit-zookeeper)" = "/data"
sudo docker compose \
  -f deploy/foundry/pours/deployment/compose.yaml \
  -f /app/signoz-runtime/docker-compose.204.override.yaml \
  config --quiet
sudo docker compose \
  -f deploy/foundry/pours/deployment/compose.yaml \
  -f /app/signoz-runtime/docker-compose.204.override.yaml \
  pull
sudo docker compose \
  -f deploy/foundry/pours/deployment/compose.yaml \
  -f /app/signoz-runtime/docker-compose.204.override.yaml \
  up -d
```

## 배포 후 확인

양쪽 서버에서 각각 실행한다.

```bash
cd /app/signoz
git log -1 --oneline
git status --short
curl -fsS http://127.0.0.1:8080/api/v1/version
sudo docker ps --format '{{.Names}} {{.Image}} {{.Status}}' | grep -E 'signoz|clickhouse|zookeeper|ingester'
sudo docker network inspect signoz-network --format '{{range .Containers}}{{.Name}} {{end}}'
sudo docker inspect signoz-telemetrystore-migrator --format '{{.State.Status}} {{.State.ExitCode}}'
mountpoint -q /data
findmnt -n -o SOURCE,FSTYPE,TARGET -T /data/sayit-clickhouse
findmnt -n -o SOURCE,FSTYPE,TARGET -T /data/sayit-sqlite
findmnt -n -o SOURCE,FSTYPE,TARGET -T /data/sayit-zookeeper
sudo docker inspect signoz-telemetrystore-clickhouse-0-0 \
  --format '{{range .Mounts}}{{if eq .Destination "/var/lib/clickhouse"}}{{.Type}} {{.Source}} {{.Destination}}{{end}}{{end}}'
sudo docker inspect signoz-signoz-0 \
  --format '{{range .Mounts}}{{if eq .Destination "/var/lib/signoz"}}{{.Type}} {{.Source}} {{.Destination}}{{end}}{{end}}'
sudo docker inspect signoz-telemetrykeeper-zookeeper-0 \
  --format '{{range .Mounts}}{{if eq .Destination "/bitnami/zookeeper"}}{{.Type}} {{.Source}} {{.Destination}}{{end}}{{end}}'
sudo docker exec signoz-telemetrystore-clickhouse-0-0 \
  clickhouse-client --query "SELECT count() FROM system.mutations WHERE NOT is_done"
sudo docker exec signoz-telemetrystore-clickhouse-0-0 \
  clickhouse-client --query "SHOW GRANTS FOR sayis"
```

확인 기준:

- API 버전이 대상 SigNoZ 버전과 일치해야 한다.
- `signoz-signoz-0`는 healthy 상태여야 한다.
- ClickHouse와 ZooKeeper는 healthy 상태여야 한다.
- ClickHouse 데이터 mount는 `bind /data/sayit-clickhouse /var/lib/clickhouse`여야 한다.
- SQLite 데이터 mount는 `bind /data/sayit-sqlite /var/lib/signoz`여야 한다.
- ZooKeeper 데이터 mount는 `bind /data/sayit-zookeeper /bitnami/zookeeper`여야 한다.
- 세 데이터 경로는 `/dev/mapper/vg_data-lv_data`의 ext4 `/data` 아래에 있어야 한다.
- migrator는 `exited 0`이어야 한다.
- 완료되지 않은 ClickHouse mutation 수는 `0`이어야 한다.
- 최신 metrics write 시각이 현재 시각으로 계속 갱신되어야 한다.
- 필수 포트와 Uptime Kuma/Prometheus collector 설정이 유지되어야 한다.
- `sayis` 계정은 `signoz_metrics`와 `signoz_traces`에 대한 `SELECT` 권한만 가져야 한다.
- 모든 SigNoZ 구성 요소와 연동 서비스는 `signoz-network`에서 공식 서비스명으로 통신해야 한다.
- 기존 `signoz-net` 네트워크가 남아 있지 않아야 한다.

## 규칙

- 항상 upstream 정식 릴리즈 태그를 먼저 확인한다.
- 배포 기준은 `upstream/main`이 아니라 릴리즈 태그다.
- 100.203과 100.204는 서로 의존하지 않는 독립 풀스택으로 배포한다.
- 내부망과 외부망 사이에 OTLP 또는 ClickHouse 직접 연결을 구성하지 않는다.
- 로컬 커스텀과 양쪽 서버의 실행 상태를 확인하기 전에는 업그레이드 완료로 보지 않는다.
- 100.203과 100.204의 compose 변경, image pull, restart는 배포 작업으로 취급한다.
- 정상 업그레이드에서는 ClickHouse 데이터를 다시 rsync하지 않는다. bind mount 유지와 `/data` mount 상태만 검증한다.
- 기존 named volume에서의 데이터 이전과 롤백은 `CLICKHOUSE_DATA_STORAGE_RUNBOOK.md` 절차를 따른다. 다른 저장소로 재이전할 때는 현재 bind mount를 새 원본으로 확인해 별도 계획을 세운다.
- ClickHouse 데이터 작업에서 `docker compose down -v`, `docker volume rm signoz-clickhouse`, 원본·대상 경로를 확인하지 않은 `rsync --delete`를 실행하지 않는다.
