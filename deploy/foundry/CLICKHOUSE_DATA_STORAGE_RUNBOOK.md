# ClickHouse 데이터 저장소 운영 런북

이 문서는 100.203과 100.204의 SigNoZ ClickHouse 데이터를 Docker named volume에서 호스트 LVM의 `/data/sayit-clickhouse`로 운영하기 위한 절차다. 정상 업그레이드와 기존 named volume에서의 초기 이전·롤백을 구분한다.

## 현재 운영 상태

확인일은 2026-09-01이다.

| 서버 | 블록 장치 | LVM | 파일시스템 | 영구 mount | ClickHouse 호스트 경로 | 전환 직후 사용량 |
| --- | --- | --- | --- | --- | --- | --- |
| 100.203 | `/dev/sdc1` | `vg_data/lv_data` | ext4 | `/data` | `/data/sayit-clickhouse` | 약 119GB, 여유 68GB |
| 100.204 | `/dev/sdc1` | `vg_data/lv_data` | ext4 | `/data` | `/data/sayit-clickhouse` | 약 1.8GB, 여유 185GB |

- 100.203 `/data` UUID: `d48f504d-9e47-425f-a169-2adc0833be7a`
- 100.204 `/data` UUID: `f2157163-5ec1-4063-a220-c8737e5efa29`
- 컨테이너 경로: `/var/lib/clickhouse`
- 전환 시 확인한 숫자 소유권·모드: `101:101:777`
- 이전 Docker 볼륨: `signoz-clickhouse`
- 이전 볼륨 데이터 경로: `/app/docker/volumes/signoz-clickhouse/_data`
- 롤백 Compose: `/app/signoz-runtime/compose.clickhouse-volume.rollback.yaml`

숫자 소유권과 모드는 새 정책값이 아니라 전환 당시 원본과 일치시킨 검증값이다. 변경이 필요하면 ClickHouse 이미지의 실제 실행 UID/GID와 기존 데이터 권한을 다시 확인한다.

## 형상관리 기준

운영 기준은 `deploy/foundry/casting.yaml`이다. Foundry가 생성한 ClickHouse named volume mount를 JSON Patch `test`로 확인한 다음 `/data/sayit-clickhouse:/var/lib/clickhouse`로 교체하고, 더 이상 쓰지 않는 ClickHouse top-level volume 선언을 제거한다.

```yaml
- op: test
  path: /services/signoz-telemetrystore-clickhouse-0-0/volumes/0
  value: signoz-telemetrystore-0-0-data:/var/lib/clickhouse
- op: replace
  path: /services/signoz-telemetrystore-clickhouse-0-0/volumes/0
  value: /data/sayit-clickhouse:/var/lib/clickhouse
- op: remove
  path: /volumes/signoz-telemetrystore-0-0-data
```

Foundry patch는 생성 후 `pours`에 쓰기 전에 적용된다. `test`가 실패하면 upstream 생성 구조가 바뀐 것이므로 patch를 제거하거나 생성 Compose를 직접 수정하지 말고 새 생성물을 비교한다.

공식 근거:

- [SigNoZ Foundry patches](https://github.com/SigNoz/foundry/blob/main/docs/concepts/patches.md)
- [SigNoZ Foundry casting](https://github.com/SigNoz/foundry/blob/main/docs/concepts/casting.md)

## 정상 SigNoZ 업그레이드

정상 업그레이드에서는 데이터 복사나 이전 볼륨 재연결을 수행하지 않는다.

1. 로컬 전용 브랜치에서 upstream 정식 릴리즈와 `casting.yaml` 변경을 반영한다.
2. `foundryctl forge`로 Compose를 다시 생성한다.
3. ClickHouse bind mount가 정확히 한 건이고 이전 named volume mount가 없는지 확인한다.
4. 양쪽 서버에서 `/data` LVM mount와 여유 공간을 확인한 뒤 배포한다.
5. 100.204에서는 기존 runtime override를 함께 적용한다.

```bash
foundryctl forge --no-updater --no-ledger \
  -f deploy/foundry/casting.yaml \
  -p deploy/foundry/pours

docker compose \
  -f deploy/foundry/pours/deployment/compose.yaml \
  config --quiet

test "$(grep -Fc '/data/sayit-clickhouse:/var/lib/clickhouse' deploy/foundry/pours/deployment/compose.yaml)" -eq 1
! grep -qE 'signoz-clickhouse|signoz-telemetrystore-0-0-data:/var/lib/clickhouse' deploy/foundry/pours/deployment/compose.yaml
```

서버 배포 전 확인:

```bash
test "$(findmnt -n -o TARGET -T /data/sayit-clickhouse)" = "/data"
test "$(findmnt -n -o SOURCE -T /data/sayit-clickhouse)" = "/dev/mapper/vg_data-lv_data"
df -hT /data
stat -c '%u:%g:%a %n' /data/sayit-clickhouse
```

ClickHouse 이미지 버전이 바뀌면 공식 릴리즈의 지원 업그레이드 경로와 디스크 여유 공간을 추가로 확인한다.

## 기존 named volume에서 초기 이전

이 절차는 ClickHouse 컨테이너의 현재 mount가 `volume signoz-clickhouse ... /var/lib/clickhouse`로 확인된 경우에만 사용한다. 현재 운영 상태처럼 이미 `/data/sayit-clickhouse` bind mount를 사용하는 서버에는 반복 실행하지 않는다. 다른 저장소로 다시 이동하려면 실제 현재 mount를 새 원본으로 정하고 별도 이전 계획을 검증한다. 정상 버전 업그레이드에는 이 절차를 사용하지 않는다.

### 1. 사전 검증

```bash
source_dir=$(sudo docker volume inspect -f '{{.Mountpoint}}' signoz-clickhouse)
target_dir=/data/sayit-clickhouse

sudo test -d "$source_dir"
test -d "$target_dir"
test "$(findmnt -n -o TARGET -T "$target_dir")" = "/data"
test "$(findmnt -n -o SOURCE -T "$target_dir")" = "/dev/mapper/vg_data-lv_data"
df -hT /data
sudo docker volume inspect signoz-clickhouse
```

이하 이전 명령은 같은 shell에서 `source_dir`와 `target_dir` 값을 유지하거나 각 명령 전에 두 값을 다시 선언한다. `source_dir`는 Docker 조회 결과로 고정하며 경로를 추정하지 않는다.

ClickHouse가 기존 볼륨을 사용 중인지, 미완료 mutation이 없는지, SigNoZ API가 정상인지 확인한다.

```bash
sudo docker inspect signoz-telemetrystore-clickhouse-0-0 \
  --format '{{range .Mounts}}{{if eq .Destination "/var/lib/clickhouse"}}{{.Type}} {{.Name}} {{.Source}} {{.Destination}}{{end}}{{end}}'
sudo docker exec signoz-telemetrystore-clickhouse-0-0 \
  clickhouse-client --query "SELECT count() FROM system.mutations WHERE NOT is_done"
curl -fsS http://127.0.0.1:8080/api/v1/health
```

### 2. 롤백 Compose 보존

100.203:

```bash
sudo install -d -m 0755 /app/signoz-runtime
sudo install -m 0644 \
  /app/signoz/deploy/foundry/pours/deployment/compose.yaml \
  /app/signoz-runtime/compose.clickhouse-volume.rollback.yaml
sudo docker compose \
  --project-directory /app/signoz/deploy/foundry/pours/deployment \
  -f /app/signoz-runtime/compose.clickhouse-volume.rollback.yaml \
  config --quiet
```

100.204는 검증 명령에 아래 파일을 추가한다.

```text
-f /app/signoz-runtime/docker-compose.204.override.yaml
```

### 3. 온라인 선복사

서비스를 유지한 상태에서 1차 복사를 수행한다. 이 단계에서는 ClickHouse 파일이 생성·정리되므로 rsync 종료 코드 24가 발생할 수 있다. 완료 판정은 서비스 정지 후 최종 동기화로 한다.

```bash
sudo rsync -aHAX --numeric-ids --delete-delay --stats \
  "$source_dir/" "$target_dir/"
```

### 4. 서비스 정지와 최종 동기화

Compose를 내릴 때 `-v` 또는 `--volumes`를 사용하지 않는다. 100.204는 runtime override를 함께 지정한다.

Docker 공식 문서상 `docker compose down`의 `-v`/`--volumes` 옵션은 Compose에 선언된 named volume과 컨테이너의 anonymous volume을 제거한다. 이 절차에서는 해당 옵션을 사용하지 않는다: [docker compose down](https://docs.docker.com/reference/cli/docker/compose/down/).

```bash
cd /app/signoz
sudo docker compose \
  -f deploy/foundry/pours/deployment/compose.yaml \
  down

test -z "$(sudo docker ps -q --filter name='^/signoz-telemetrystore-clickhouse-0-0$')"

sudo rsync -aHAX --numeric-ids --delete --stats \
  "$source_dir/" "$target_dir/"

sudo rsync -aHAXn --numeric-ids --delete --itemize-changes \
  "$source_dir/" "$target_dir/"
```

최종 rsync는 종료 코드 `0`이어야 하고, 바로 뒤 dry-run은 출력이 없어야 한다. 원본과 대상의 `stat -c '%u:%g:%a'`와 `du -sh`도 비교한다.

### 5. 단계별 기동

ClickHouse만 먼저 기동하여 bind mount와 데이터 조회를 검증한 뒤 전체 스택을 기동한다.

```bash
sudo docker compose \
  -f deploy/foundry/pours/deployment/compose.yaml \
  up -d signoz-telemetrystore-clickhouse-0-0

sudo docker inspect signoz-telemetrystore-clickhouse-0-0 \
  --format '{{.State.Health.Status}}'
sudo docker inspect signoz-telemetrystore-clickhouse-0-0 \
  --format '{{range .Mounts}}{{if eq .Destination "/var/lib/clickhouse"}}{{.Type}} {{.Source}} {{.Destination}}{{end}}{{end}}'
sudo docker exec signoz-telemetrystore-clickhouse-0-0 \
  clickhouse-client --query "SELECT version()"

sudo docker compose \
  -f deploy/foundry/pours/deployment/compose.yaml \
  up -d
```

100.204는 두 명령 모두 runtime override를 함께 지정한다.

## 전환 후 검증

```bash
curl -fsS http://127.0.0.1:8080/api/v1/health
sudo docker inspect signoz-signoz-0 --format '{{.State.Health.Status}}'
sudo docker inspect signoz-telemetrystore-clickhouse-0-0 --format '{{.State.Health.Status}}'
sudo docker inspect signoz-telemetrystore-migrator --format '{{.State.Status}} {{.State.ExitCode}}'
sudo docker exec signoz-telemetrystore-clickhouse-0-0 \
  clickhouse-client --query "SELECT count() FROM system.mutations WHERE NOT is_done"
sudo docker exec signoz-telemetrystore-clickhouse-0-0 \
  clickhouse-client --query "SELECT count(), sum(rows), sum(bytes_on_disk) FROM system.parts WHERE active"
sudo docker volume inspect signoz-clickhouse
df -hT /data
```

완료 기준:

- SigNoZ와 ClickHouse health가 `healthy`다.
- SigNoZ API가 `{"status":"ok"}`를 반환한다.
- ClickHouse mount가 `bind /data/sayit-clickhouse /var/lib/clickhouse`다.
- migrator 종료 코드가 `0`이다.
- 미완료 mutation이 `0`이다.
- 전환 전후 데이터 집계가 연속적이고 신규 데이터가 다시 증가한다.
- 이전 `signoz-clickhouse` 볼륨이 그대로 존재한다.

## 롤백

이전 `signoz-clickhouse` 볼륨은 전환 직전 시점의 데이터만 가진다. 새 bind mount에서 쓰기가 재개된 뒤 이전 볼륨을 그대로 재연결하면 전환 이후 데이터가 누락된다.

- 새 ClickHouse가 쓰기 전에 기동에 실패한 경우에만 보존한 롤백 Compose로 즉시 되돌릴 수 있다.
- 새 경로에서 쓰기가 시작된 뒤에는 임의로 이전 볼륨을 재연결하지 않는다.
- 이 경우 현재 서비스를 정지하고 신규 데이터를 어떻게 보존할지 결정한 뒤, 승인된 방향으로 동기화하거나 bind mount 구성을 복구한다.

100.203의 쓰기 전 롤백 기동 예시:

```bash
sudo docker compose \
  -f /app/signoz/deploy/foundry/pours/deployment/compose.yaml \
  down
sudo docker compose \
  --project-directory /app/signoz/deploy/foundry/pours/deployment \
  -f /app/signoz-runtime/compose.clickhouse-volume.rollback.yaml \
  up -d
```

100.204는 양쪽 명령에 runtime override를 함께 지정한다. 롤백할 때도 `-v`를 사용하지 않는다.

## 이전 볼륨 보존과 제거

`signoz-clickhouse` 볼륨 삭제는 이 전환 작업의 범위가 아니다. 보존 기간, 별도 백업, 복구 시험과 사용자 승인이 모두 확인된 별도 작업에서만 제거한다.

```bash
sudo docker volume inspect signoz-clickhouse
```

운영 중인 ClickHouse가 bind mount를 사용한다는 사실만으로 이전 볼륨을 자동 삭제하지 않는다.
