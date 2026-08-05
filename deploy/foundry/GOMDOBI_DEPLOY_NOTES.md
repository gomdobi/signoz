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

- 확인일: 2026-08-05
- upstream 릴리즈 태그: `v0.135.1`
- foundryctl: `v0.2.17`
- 100.203/100.204 SigNoZ 이미지: `signoz/signoz:v0.135.1`
- 100.203/100.204 collector 이미지: `signoz/signoz-otel-collector:v0.144.6`
- 100.203/100.204 ClickHouse 이미지: `clickhouse/clickhouse-server:25.12.5`
- 100.203/100.204 ZooKeeper 이미지: `signoz/zookeeper:3.7.1`
- 100.203/100.204 Docker 네트워크: `signoz-network`

## Foundry 파일

- casting: `deploy/foundry/casting.yaml`
- generated compose: `deploy/foundry/pours/deployment/compose.yaml`
- ingester config: `deploy/foundry/pours/deployment/ingester/ingester.yaml`
- ClickHouse config: `deploy/foundry/pours/deployment/telemetrystore/clickhouse/config-0-0.yaml`

## 반드시 유지할 커스텀

### `deploy/foundry/casting.yaml`

- `metastore.kind`는 `sqlite`를 사용한다.
- `telemetrykeeper.kind`는 기존 데이터 볼륨 재사용을 위해 `zookeeper`를 사용한다.
- ClickHouse macro는 기존 값과 일치해야 한다.
  - `shard: "01"`
  - `replica: "example01-01-1"`
- 기존 Docker 볼륨 이름을 그대로 사용해야 한다.
  - `signoz-clickhouse`
  - `signoz-sqlite`
  - `signoz-zookeeper-1`
- Docker 네트워크는 Foundry 공식 이름인 `signoz-network`를 사용한다.

### `deploy/foundry/pours/deployment/compose.yaml`

- `signoz-signoz-0.image`는 대상 SigNoZ 버전과 일치해야 한다.
- `ingester.image`와 `signoz-telemetrystore-migrator.image`는 collector 기준 버전과 일치해야 한다.
- ClickHouse 포트는 아래 포트를 노출해야 한다.
  - `9000:9000`
  - `8123:8123`
  - `9181:9181`
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

3. 커스텀 유지 여부를 확인한다.

```bash
grep -nE 'signoz/signoz:v|signoz-otel-collector:v|clickhouse/clickhouse-server:|signoz/zookeeper:|9000:9000|8123:8123|9181:9181|8889:8889|uptime_kuma_api_key' deploy/foundry/pours/deployment/compose.yaml
grep -nE 'job_name: uptime-kuma|password_file: /app/secrets/uptime_kuma_api_key|endpoint: 0.0.0.0:8889|prometheus' deploy/foundry/pours/deployment/ingester/ingester.yaml
grep -nE 'replica: example01-01-1|shard: "01"' deploy/foundry/pours/deployment/telemetrystore/clickhouse/config-0-0.yaml
```

## 100.203/100.204 공통 준비

양쪽 서버 모두 `/app/signoz`를 `origin/main`과 일치시킨 뒤 공식 Foundry 산출물을 생성하고 검증한다.

```bash
cd /app/signoz
sudo git pull --ff-only origin main
sudo foundryctl forge --no-updater --no-ledger \
  -f deploy/foundry/casting.yaml \
  -p deploy/foundry/pours
sudo docker compose \
  -f deploy/foundry/pours/deployment/compose.yaml \
  config --quiet
```

## 100.203 내부망 풀스택 배포

```bash
cd /app/signoz
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
sudo docker exec signoz-telemetrystore-clickhouse-0-0 \
  clickhouse-client --query "SELECT count() FROM system.mutations WHERE NOT is_done"
```

확인 기준:

- API 버전이 대상 SigNoZ 버전과 일치해야 한다.
- `signoz-signoz-0`는 healthy 상태여야 한다.
- ClickHouse와 ZooKeeper는 healthy 상태여야 한다.
- migrator는 `exited 0`이어야 한다.
- 완료되지 않은 ClickHouse mutation 수는 `0`이어야 한다.
- 최신 metrics write 시각이 현재 시각으로 계속 갱신되어야 한다.
- 필수 포트와 Uptime Kuma/Prometheus collector 설정이 유지되어야 한다.
- 모든 SigNoZ 구성 요소와 연동 서비스는 `signoz-network`에서 공식 서비스명으로 통신해야 한다.
- 기존 `signoz-net` 네트워크가 남아 있지 않아야 한다.

## 규칙

- 항상 upstream 정식 릴리즈 태그를 먼저 확인한다.
- 배포 기준은 `upstream/main`이 아니라 릴리즈 태그다.
- 100.203과 100.204는 서로 의존하지 않는 독립 풀스택으로 배포한다.
- 내부망과 외부망 사이에 OTLP 또는 ClickHouse 직접 연결을 구성하지 않는다.
- 로컬 커스텀과 양쪽 서버의 실행 상태를 확인하기 전에는 업그레이드 완료로 보지 않는다.
- 100.203과 100.204의 compose 변경, image pull, restart는 배포 작업으로 취급한다.
