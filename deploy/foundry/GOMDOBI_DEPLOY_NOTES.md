# GOMDOBI SigNoZ Foundry 배포 메모

이 저장소의 업그레이드와 배포 흐름은 아래 체인으로 본다.

```text
SigNoZ/signoz upstream 릴리즈 태그 -> gomdobi/signoz main -> 100.203:/app/signoz
```

- `100.203`: 메인 SigNoZ 서버
- `100.204`: 외부망 collector-only 서버

업그레이드 기준은 upstream 정식 릴리즈 태그다. `v0.130.1`부터 upstream의 legacy Docker Compose 파일은 제거되고 Foundry 기준으로 전환되었으므로, 100.203은 `deploy/foundry` 기준으로 배포한다.

## 현재 배포 기준

- 확인일: 2026-07-13
- upstream 릴리즈 태그: `v0.132.2`
- 100.203 SigNoZ 이미지: `signoz/signoz:v0.132.2`
- 100.203 collector 이미지: `signoz/signoz-otel-collector:v0.144.5`
- 100.203 ClickHouse 이미지: `clickhouse/clickhouse-server:25.12.5`
- 100.203 ZooKeeper 이미지: `signoz/zookeeper:3.7.1`
- 100.204 collector-only 이미지: `signoz/signoz-otel-collector:v0.144.5`

## v0.131.0 ClickHouse 주의사항

SigNoZ `v0.131.0`은 bundled ClickHouse를 `25.12.5`로 올린다. GOMDOBI 운영 기준에서는 full volume tar 백업을 기본으로 하지 않는다. 기존 Docker volume을 삭제하지 않고 보존한 상태에서 Foundry 산출 compose로 컨테이너만 재생성한다.

데이터 보존이 필요한 경우에만 별도 백업을 수행한다. 백업 대상 볼륨:

- `signoz-clickhouse`
- `signoz-zookeeper-1`
- `signoz-sqlite`
- `signoz-telemetrystore-user-scripts`

100.221 테스트에서는 `v0.130.1`에서 `v0.131.0`으로 올린 뒤 API 버전 `v0.131.0`, ClickHouse `25.12.5.44`, migrator exit code `0`, 최근 metrics write를 확인했다.

100.203 실 배포에서는 full volume tar 백업 없이 기존 볼륨을 유지한 채 컨테이너를 재생성했다. 배포 후 API 버전 `v0.131.0`, ClickHouse `25.12.5.44`, migrator exit code `0`, 최근 metrics write를 확인했다.

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
- 기존 Uptime Kuma/Prometheus/Grafana와 같은 Docker 네트워크를 유지하기 위해 compose network name은 `signoz-net`을 사용하고 `external: true`로 둔다.

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
- compose network name은 `signoz-net`이어야 하며 `external: true`여야 한다.
- 기존 내부 서비스명 호환을 위해 alias `signoz`, `signoz-otel-collector`, `otel-collector`, `zookeeper-1`, `clickhouse`를 유지한다.

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

## 100.203 배포

100.203은 `/app/signoz` 기준으로 배포한다. 기본 절차는 기존 Docker volume을 유지하고 컨테이너만 재생성한다.

```bash
cd /app/signoz
git -C /app/signoz pull --ff-only origin main
foundryctl cast --no-updater --no-ledger -f deploy/foundry/casting.yaml -p deploy/foundry/pours
```

기존 legacy compose에서 Foundry로 전환하는 첫 배포에서는 기존 컨테이너를 먼저 내린 뒤 Foundry stack을 올린다. 기존 데이터 볼륨은 유지한다.

배포 후 확인:

```bash
cd /app/signoz
git log -1 --oneline
git status --short
curl -fsS http://127.0.0.1:8080/api/v1/version
docker ps --format '{{.Names}} {{.Image}} {{.Status}}' | grep -E 'signoz|clickhouse|zookeeper|ingester'
docker volume ls --format '{{.Name}}' | grep -E '^signoz-(clickhouse|sqlite|zookeeper-1)$'
```

확인 기준:

- API 버전이 대상 SigNoZ 버전과 일치해야 한다.
- `signoz-signoz-0`는 healthy 상태여야 한다.
- ClickHouse와 ZooKeeper는 healthy 상태여야 한다.
- 기존 세 데이터 볼륨 이름이 유지되어야 한다.
- 필수 포트와 Uptime Kuma/Prometheus collector 설정이 유지되어야 한다.

## 100.204 collector-only 확인

100.204는 별도 collector-only 운영 파일을 사용한다. collector 이미지 태그가 바뀐 경우에만 갱신하고, 태그 변경이 없으면 상태 확인만 한다.

```bash
cd /app/signoz/deploy/docker
grep -nE 'signoz-otel-collector|4317|4318|8889' docker-compose.collector-only.yaml
docker compose -f docker-compose.collector-only.yaml config --quiet
docker ps --format '{{.Names}} {{.Image}} {{.Status}}' | grep -E 'signoz|collector'
```

## 규칙

- 항상 upstream 정식 릴리즈 태그를 먼저 확인한다.
- 배포 기준은 `upstream/main`이 아니라 릴리즈 태그다.
- 로컬 커스텀과 양쪽 대상 서버를 확인하기 전에는 업그레이드 완료로 보지 않는다.
- 100.203과 100.204의 compose 변경, image pull, restart는 배포 작업으로 취급한다.
