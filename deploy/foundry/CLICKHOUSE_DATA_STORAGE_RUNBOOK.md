# ClickHouse 데이터 저장소 운영 런북

이 문서는 100.203과 100.204의 SigNoZ ClickHouse 데이터를 Docker named volume에서 호스트 LVM의 `/data/sayit-clickhouse`로 운영하기 위한 절차다. 정상 업그레이드와 기존 named volume에서의 초기 이전·롤백을 구분한다.

## 저장소 전환 당시 상태

확인일은 2026-09-01이다. 표의 사용량·장치 정보는 전환 당시 값이며 현재 용량으로 재사용하지 않는다. 이후 배포·복제 오류 정리·보관본 삭제 이력은 [배포 메모](GOMDOBI_DEPLOY_NOTES.md)를 확인한다.

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
4. 승인된 대상 서버에서 `/data` LVM mount와 여유 공간을 확인한 뒤 배포한다. 한 서버의 승인을 다른 서버 배포로 확대하지 않는다.
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

ClickHouse 서비스를 지정하여 bind mount와 데이터 조회를 검증한 뒤 전체 스택을 기동한다. 현재 생성 Compose의 `depends_on`에 따라 ZooKeeper와 user-scripts 준비 서비스도 함께 기동될 수 있으므로, 이 단계를 ClickHouse 컨테이너만 실행하는 것으로 해석하지 않는다.

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

## 복제 대기열의 유실 파트 반복 오류 정리

2026-09-08의 204 처리 사례에 대한 재발 진단·작업 기준이다. 무조건 실행하는 초기화 절차가 아니다. 당시에는 정상 데이터가 남은 6개 파티션, replica 1개씩, readonly/session-expired `0`을 확인하고 사용자 승인으로 파티션을 재등록했다. 적용 대상과 전후 행 수는 [배포 메모](GOMDOBI_DEPLOY_NOTES.md)에 기록했다.

### 조회와 판정

승인된 서버에서 현재 대기열과 replica 상태를 먼저 조회한다. 오류 정리나 데이터 유실 수용 지시를 다른 파티션·서버의 삭제 승인으로 확대하지 않는다.

```sql
SELECT database, table, type, create_time, new_part_name, num_tries,
       last_attempt_time, splitByChar('\n', last_exception)[1] AS error,
       num_postponed, postpone_reason
FROM system.replication_queue
ORDER BY database, table, create_time;

SELECT database, table, replica_name, is_leader, total_replicas, active_replicas,
       is_readonly, is_session_expired, queue_size, absolute_delay
FROM system.replicas
ORDER BY database, table;
```

대기열 컬럼의 의미는 [ClickHouse 공식 system.replication_queue 문서](https://clickhouse.com/docs/reference/system-tables/replication_queue)를 기준으로 한다.

- 대기열 `6건`은 실패 작업 수이며 유실 행 수가 아니다. 대상 파트 이름, 실제 partition ID, 엔진·키, 정상 active 파트와 기존 detached 항목을 대조한다. 다른 replica에 정상 사본이 있는지도 확인한다.
- 정상 병합 작업은 대기열에 일시적으로 나타날 수 있다. `SYSTEM STOP MERGES` 중에는 정상 병합 대기열도 남을 수 있으므로, 재개 전 전체 대기열이 반드시 `0`이어야 한다는 검증을 넣지 않는다.
- `GET_PART` 항목이나 ZooKeeper 노드를 직접 삭제하지 않는다. 정상 파트와 범위가 겹치는 유실 파트 이름을 근거로 `DROP PART`·`DROP PARTITION`을 실행하지 않는다. Altinity의 [복제 문제 진단 문서](https://kb.altinity.com/altinity-kb-setup-and-maintenance/altinity-kb-check-replication-ddl-queue/)는 남은 파티션의 누락 파트 사례에 `DETACH/ATTACH`를 제시하며, fetch 대기열의 수동 삭제는 피하도록 안내한다.

### 승인된 파티션 재등록 시 확인할 사항

1. 대상 DB·테이블·partition ID와 영향 범위를 고정한다. `PARTITION ID 'all'`은 파티션이 없는 테이블의 전체 데이터 범위일 수 있다. 다중 replica 환경에서는 이 204 단일 replica 사례를 그대로 적용하지 않는다.
2. 수집기와 SigNoZ 정지 및 대상 테이블 merges 일시 정지 후 진행 중인 쓰기·병합이 없는지 확인한다. 이 SQL 작업에는 ClickHouse와 ZooKeeper가 실행 중이어야 한다.
3. 실제 `system.tables.data_paths`와 Docker mount를 확인한다. 기존 detached 항목이 재등록 데이터에 섞이지 않게 분리한다. 복사·보관·삭제는 해당 작업의 승인 범위를 따르며 유실된 과거 데이터를 임의로 되살리지 않는다.
4. 파티션마다 `DETACH → ATTACH → 전후 비교 → CHECK TABLE`을 완료한 뒤 다음 대상으로 진행한다. `DETACH`는 데이터를 detached로 옮기며, `ATTACH`로 등록하기 전에는 조회 대상에서 빠진다. 이 명령은 replica에 전파되므로 영향 범위를 먼저 확인한다. [ClickHouse 공식 PARTITION 문서](https://clickhouse.com/docs/reference/statements/alter/partition)
5. merges를 정지한 동안 대상 파티션별 총 행 수와 데이터가 있는 파트의 `(rows, bytes_on_disk, hash_of_all_files)` 정렬 목록을 비교한다. 재등록 후 part 이름은 달라질 수 있으므로 이름만 비교하지 않는다. 204 사례의 hash 비교는 `rows > 0`인 파트를 대상으로 했고, 이 검증은 기존 유실 데이터가 복구됐다는 뜻이 아니다.
6. 모든 대상이 등록됐고 데이터 검증이 통과하면 merges와 원래 서비스를 재개한다. API·Collector health, 신규 Infrastructure 메트릭·트레이스, 복제 예외·지연, 관찰 구간의 반복 로그를 확인한다. 관찰 시각과 범위를 결과에 남긴다.

### 검사 출력과 중단 처리

204에서 사용한 무결성 검사 예시다. 다른 작업에서는 승인된 실제 테이블과 partition ID로 대상을 먼저 확정한다.

```sql
CHECK TABLE signoz_metrics.metadata PARTITION ID '20260818'
SETTINGS check_query_single_value_result = 1
FORMAT TSV;
```

`check_query_single_value_result=1`을 명시하면 단일 결과 `1`/`0`으로 판정할 수 있다. 값 `0`의 상세 모드는 파트별 `part_path`, `is_passed`, `message`를 반환하므로 출력 전체를 문자열 `1`과 비교하면 안 된다. 명령 종료 코드와 검사 결과를 각각 확인한다. [ClickHouse 공식 CHECK TABLE 문서](https://clickhouse.com/docs/reference/statements/check-table)

- 출력 형식과 오류 처리 분기는 서비스를 정지하기 전에 검증한다. 204 작업에서는 이 판정 버그로 스크립트가 중간 종료되어 정지 요청 17:45부터 서비스 재시작 19:58(KST)까지 이어졌다.
- 검증 실패 시 이미 완료된 대상과 아직 detached인 대상을 구분한다. 단순 출력 판정 버그를 데이터 손상으로 단정하거나, 완료된 `DETACH/ATTACH`를 처음부터 재실행하지 않는다.
- 데이터 미등록·불일치 상태에서는 서비스를 무조건 시작하지 않는다. 반대로 모든 데이터의 정상 등록·검증이 확인됐으면 출력 형식 교정 때문에 정지 상태로 방치하지 않고 merges·서비스를 재개한다. 중단 시 현재 데이터 상태와 서비스 상태를 즉시 보고한다.

### 유실 데이터와 보관본 처리 범위

2026-09-09 사용자 지시에 따라 이번 204 유실 데이터는 복구하지 않는다. 정리 작업 보관본 `/data/signoz-replication-cleanup-204-20260908.ktQtKNHk` 107MB는 이미 영구 삭제했으며 복구 원본으로 사용할 수 없다. 이 결정은 해당 사건의 데이터·보관본에 한정하며, 다른 업그레이드 보관본이나 이전 Docker 볼륨의 일괄 삭제 또는 전역 백업 정책 변경을 뜻하지 않는다.

보관본 삭제 지시를 받으면 실제 경로, symlink·하위 mount 여부, 현재 서비스가 쓰는 경로와의 분리를 확인하고 지정된 보관본만 삭제한다. 삭제 후 경로 부재와 서비스 상태를 확인한다. 승인된 삭제가 끝난 보관본을 계속 보관 중이라고 문서에 남기지 않는다.
