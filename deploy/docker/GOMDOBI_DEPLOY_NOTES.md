# GOMDOBI SigNoz 업그레이드 메모

이 저장소의 업그레이드와 배포 흐름은 아래 체인으로 본다.

```text
SigNoz/signoz upstream 릴리즈 태그 -> gomdobi/signoz main -> 100.203:/app/signoz
```

- `100.203`: 메인 SigNoz 서버
- `100.204`: 외부망 collector-only 서버

업그레이드 기준은 upstream 정식 릴리즈 태그다. upstream 병합 후에는 아래 로컬 배포 커스텀이 유지되는지 확인해야 업그레이드 완료로 본다.

## 현재 배포 기준

- 확인일: 2026-06-15
- upstream 릴리즈 태그: `v0.128.0`
- `gomdobi/signoz` 커밋: `e163533de4a8819dd0d2083cd1c302d2b16848e5`
- 100.203 `/app/signoz` 커밋: `e163533de`
- 100.203 SigNoz API 버전: `v0.128.0`
- 100.203 SigNoz 이미지: `signoz/signoz:v0.128.0`
- 100.203 collector 이미지: `signoz/signoz-otel-collector:v0.144.5`
- 100.203 ClickHouse 이미지: `clickhouse/clickhouse-server:25.5.6`
- 100.203 ZooKeeper 이미지: `signoz/zookeeper:3.7.1`
- 100.204 collector-only 이미지: `signoz/signoz-otel-collector:v0.144.5`

## 반드시 유지할 커스텀

### `deploy/docker/docker-compose.yaml`

- `clickhouse.ports`는 아래 포트를 노출해야 한다.
  - `9000:9000`
  - `8123:8123`
  - `9181:9181`
- `otel-collector.volumes`에는 아래 secret mount가 있어야 한다.
  - `/app/secrets/uptime_kuma_api_key:/app/secrets/uptime_kuma_api_key:ro`
- `otel-collector.ports`는 아래 포트를 노출해야 한다.
  - `4317:4317`
  - `4318:4318`
  - `8889:8889`

### `deploy/docker/otel-collector-config.yaml`

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
curl -fsSI -L https://github.com/SigNoz/signoz/releases/tag/<target-version>
```

2. 현재 배포 버전과 대상 upstream compose 버전을 비교한다.

```bash
grep -nE 'signoz/signoz:|signoz-otel-collector|clickhouse/clickhouse-server|signoz/zookeeper' deploy/docker/docker-compose.yaml
curl -fsSL https://raw.githubusercontent.com/SigNoz/signoz/<target-version>/deploy/docker/docker-compose.yaml \
  | grep -nE 'signoz/signoz:|signoz-otel-collector|clickhouse/clickhouse-server|signoz/zookeeper'
```

3. 로컬과 fork 상태를 확인한다.

```bash
git status --short
git branch --show-current
git log -1 --oneline --decorate
git ls-remote --heads origin main
git ls-remote --heads upstream main
```

4. 릴리즈 태그를 병합한다.

```bash
git switch main
git pull --ff-only origin main
git merge --no-edit <target-version>
```

commit hook이 `main` merge commit을 막으면 먼저 merge 상태와 diff를 확인한 뒤 `--no-verify`로 merge commit을 완료한다.

5. commit 또는 push 전에 커스텀 유지 여부를 확인한다.

```bash
grep -nE '9000:9000|8123:8123|9181:9181|uptime_kuma_api_key|8889:8889|VERSION:-|OTELCOL_TAG:-' deploy/docker/docker-compose.yaml
grep -nE 'job_name: uptime-kuma|password_file: /app/secrets/uptime_kuma_api_key|endpoint: 0.0.0.0:8889|signozclickhousemetrics, metadataexporter, signozmeter, prometheus' deploy/docker/otel-collector-config.yaml
git diff --cached -- deploy/docker/docker-compose.yaml deploy/docker/otel-collector-config.yaml
```

6. `gomdobi/signoz`에 push한다.

```bash
git status --short
git log -1 --oneline --decorate
git push origin main
```

## 100.203 배포

100.203은 `/app/signoz` 기준으로 배포한다.

```bash
ssh net100-203
cd /app/signoz
sudo git -C /app/signoz -c safe.directory=/app/signoz pull --ff-only origin main
sudo docker compose -f deploy/docker/docker-compose.yaml config --quiet
sudo docker compose -f deploy/docker/docker-compose.yaml pull signoz
sudo docker compose -f deploy/docker/docker-compose.yaml up -d
```

배포 후 확인:

```bash
cd /app/signoz
git log -1 --oneline
git status --short
curl -fsS http://127.0.0.1:8080/api/v1/version
sudo docker ps --format '{{.Names}} {{.Image}} {{.Status}}' | grep -E 'signoz|clickhouse|zookeeper'
```

확인 기준:

- `signoz` 이미지가 대상 SigNoz 버전과 일치해야 한다.
- `signoz-otel-collector` 이미지가 upstream compose와 일치해야 한다.
- `signoz`는 healthy 상태여야 한다.
- ClickHouse와 ZooKeeper는 healthy 상태를 유지해야 한다.
- 필수 포트와 Uptime Kuma/Prometheus collector 설정이 유지되어야 한다.

## 100.204 collector-only 배포

100.204는 아래 파일을 사용한다.

```text
/app/signoz/deploy/docker/docker-compose.collector-only.yaml
```

upstream collector 태그가 바뀐 경우에만 100.204를 갱신한다.

```bash
ssh net100-204
cd /app/signoz/deploy/docker
grep -nE 'signoz-otel-collector|v0\.144\.|4317|4318|8889' docker-compose.collector-only.yaml
sudo docker compose -f docker-compose.collector-only.yaml config --quiet
sudo docker compose -f docker-compose.collector-only.yaml pull
sudo docker compose -f docker-compose.collector-only.yaml up -d
sudo docker ps --format '{{.Names}} {{.Image}} {{.Status}}' | grep -E 'signoz|collector'
```

## 완료 근거

업그레이드 후 아래 사실을 남긴다.

- upstream 릴리즈 태그
- `gomdobi/signoz` push 커밋
- 100.203 `/app/signoz` 커밋
- 100.203 SigNoz API 버전
- 100.203 실행 컨테이너 이미지
- 100.204 실행 collector 이미지
- 커스텀 유지 검증 결과

## 규칙

- 항상 upstream 정식 릴리즈 태그를 먼저 확인한다.
- 배포 기준은 `upstream/main`이 아니라 릴리즈 태그다.
- 로컬 커스텀과 양쪽 대상 서버를 확인하기 전에는 업그레이드 완료로 보지 않는다.
- 100.203과 100.204의 compose 변경, image pull, restart는 배포 작업으로 취급한다.
- 이 메모는 `signoz/signoz` 업그레이드와 100.203/100.204 배포 절차만 다룬다.
