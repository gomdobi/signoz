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

## 최종 확인 요약

- 2026-09-10 배포 검증 기준: 203·204 모두 SigNoZ `v0.141.1`, Collector / migrator `v0.144.9`다. ClickHouse `25.12.5`, ZooKeeper `3.7.1`, foundryctl `v0.2.17`은 유지했다.
- 이번 `v0.141.1` 변경과 배포 기록은 전용 작업 브랜치 `codex/upgrade-signoz-v0.141.1-203-204`에서 준비했으며, 배포 완료 후 사용자가 `main` 병합을 별도로 승인했다. 이전 `v0.140.0` 배포 기록은 `main`의 `a72387f076`에, 후속 정리 기록은 `eecd3aa260`에 반영돼 있다.
- 204의 기존 복제 오류 6건은 2026-09-08 별도 승인 작업으로 정리됐다. 2026-09-09에는 해당 작업 보관본 107MB만 사용자 지시로 영구 삭제했다.
- 아래 수치와 상태는 각 작업 당시 실행 결과다. 문서 갱신 자체를 서버 재검증이나 재배포로 보지 않는다.

## 2026-09-10 203·204 Docker 업그레이드

- 배포 승인 범위는 203·204의 기존 Docker/Foundry 배포다. 저장소 반영은 배포 완료 후 별도 승인된 작업이며, 병합을 이유로 서버를 다시 배포하지 않는다.
- SigNoZ `v0.140.0` → `v0.141.1`만 변경했다. 로컬과 서버에서 공식 `foundryctl v0.2.17 forge --no-updater --no-ledger`를 사용했고, Compose 검증은 종료 코드 `0`이었다.
- 배포 전 양쪽 서버의 casting과 기본 Compose는 바이트 단위로 로컬 `origin/main` 기준과 일치했다. 203의 기존 미커밋 변경은 보관본의 Git patch와 Foundry 파일 복사본에 보존하고, 두 서버 모두 새 작업 브랜치를 만든 뒤 casting 버전만 변경했다. 서버 Git 이력을 다른 커밋으로 강제 동기화하지 않았다.
- 적용 전후 유효 Compose를 JSON으로 비교해 SigNoZ 이미지 외의 변경이 없음을 확인했다. ingester·OpAMP·ClickHouse 생성 설정과 204 전용 override는 바이트 단위로 동일하다.
- ingester와 SigNoZ만 정지한 뒤 SQLite 디렉토리를 복사했다. 정지 상태 원본/복사본 일치와 백업 SQLite `quick_check=ok`를 확인한 후 SigNoZ를 재생성하고 기존 ingester를 재개했다.
- ClickHouse·ZooKeeper는 컨테이너 ID와 시작 시각을 유지했다. Collector 이미지·컨테이너 ID도 유지했다. telemetrystore migrator는 이번에 재실행하지 않았으며, 기존 `exited 0` 상태를 유지했다.

### 정지 상태 백업 및 기동 시간

| 서버 | 보관 경로 | SQLite 보관 크기 | 정지 요청 → health 확인(KST) |
| --- | --- | --- | --- |
| 203 | `/app/signoz-runtime/upgrade-v0.141.1-FMbEuU` | 5.4MB | 11:58:29 → 11:58:57 |
| 204 | `/app/signoz-runtime/upgrade-v0.141.1-b499WP` | 948KB | 11:59:22 → 11:59:51 |

- 보관 디렉토리는 root 전용이며 `sqlite/`, 변경 전 Foundry 파일, 유효 Compose, Git 상태/patch, ClickHouse 스키마, `sayis` 권한이 포함된다. 204는 전용 override도 포함한다. ClickHouse 전체 데이터 백업이 아니다.
- 시간은 정지 요청부터 Docker health 확인까지이며, 실제 수집 누락량을 측정한 값은 아니다. Collector health의 `upSince`는 203 11:58:56, 204 11:59:51(KST)이다.
- 새 설정 DB 변경 7개(공식 소스 파일 번호 `120`~`126`)가 양쪽 SQLite의 migration 테이블에 모두 기록됐다. 해당 변경의 `Down`은 원복을 구현하지 않으므로 이전 이미지 교체만으로 DB가 되돌아가지는 않는다. 위 정지 상태 백업을 복구 기준으로 보존한다.

### 배포 후 검증

- 양쪽 SigNoZ API `v0.141.1` / health `ok`, Docker health `healthy`, Collector health `Server available`. SigNoZ·Collector restart count는 `0`이다.
- SQLite `quick_check=ok`. 기존 레코드 ID 목록을 백업과 대조했다. 203은 organization 1, 사용자 11, 대시보드 14, 알림 규칙 1, 알림 채널 4, Quick Filter 5개가 유지됐다. 204는 각각 1, 1, 1, 0, 0, 5개가 유지됐다. 기존 알림 채널 이름은 새 `display_name`에 동일하게 보존됐다.
- 양쪽 ClickHouse 테이블 135개의 engine/key/View 생성 SQL을 포함한 스키마가 배포 전후 동일하고 `sayis` SELECT 권한도 동일하다. 복제 대기열·대기열 오류·readonly/session-expired replica·최대 복제 지연·미완료 mutation은 모두 `0`이었다.
- `/data` LVM 마운트와 ClickHouse·SQLite·ZooKeeper bind mount는 유지됐다. Docker mount 배열은 반환 순서가 달라질 수 있으므로 destination으로 정렬하여 속성을 비교했다.
- 최종 확인 구간의 Collector 전송 실패·수신 거부 지표는 203 13개, 204 9개 모두 `0`이었다.

| 서버 / 조회 시각(KST) | 최근 2분 CPU 메트릭 | 메모리 메트릭 | 네트워크 메트릭 | 트레이스 | 로그 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 203 / 12:02:13 | 21,376 | 10,048 | 10,796 | 818 | 66 |
| 204 / 12:02:01 | 296 | 174 | 152 | 29 | 0 |

- CPU·메모리·네트워크는 각각 `system.cpu.time`, `system.memory.usage`, `system.network.io`의 실제 `samples_v4` 행 수다. 204에도 Infrastructure 메트릭과 트레이스가 유입된다. 204의 새 로그 유입은 이 구간에서 확인되지 않았다.
- 기동 중 양쪽 SigNoZ에 active-query 로그 디렉토리 생성 오류와 active license 조회 오류가 각각 1건 있었다. Collector에는 기존 라이브러리 capabilities 경고와 SigNoZ 준비 전 OpAMP 연결 재시도가 있었다. 최종 조회 시 양쪽 SigNoZ·Collector 최근 2분 ERROR는 `0`건이었다. 관련 설정을 임의 변경하지 않았다.

## 2026-09-09 100.204 정리 작업 보관본 삭제

- 사용자 지시: 이번 유실 데이터는 복구하지 않으며 정리 작업 보관본도 보관하지 않는다.
- 삭제 대상: `/data/signoz-replication-cleanup-204-20260908.ktQtKNHk` 전체 107MB. 기존 분리 파트, 작업 전 정상 파트 복사본, 전후 비교 파일과 작업 로그가 들어 있던 경로다.
- 삭제 전 실제 경로·디렉토리 내용·별도 mount 여부와 ClickHouse의 현재 bind mount를 확인했다. 삭제 명령 종료 코드 `0`, 대상 경로 부재, SigNoZ API health `ok`를 확인했다. 해당 보관본을 통한 복구는 불가능하다.
- 현재 데이터 `/data/sayit-clickhouse`, SQLite·ZooKeeper 데이터, 203은 변경하지 않았다. 이전 업그레이드 보관 디렉토리와 Docker named volume은 이번 삭제 대상이 아니며, 현재 잔존 여부를 재조회한 것은 아니다.

## 2026-09-08 100.204 복제 오류 정리 완료

목적은 유실된 과거 파트 복구가 아니라 `NO_REPLICA_HAS_PART` 반복 재시도 종료다. 대상은 204의 아래 6개 파티션으로 한정했다. 203은 작업하지 않았다.

| 테이블 | partition ID | 재등록 전후 유지된 행 수 |
| --- | --- | ---: |
| `signoz_metrics.metadata` | `20260818` | 15,552 |
| `signoz_metrics.samples_v4` | `20260818` | 9,095,323 |
| `signoz_metrics.samples_v4_agg_30m` | `20260818` | 173,117 |
| `signoz_metrics.samples_v4_agg_5m` | `20260818` | 973,694 |
| `signoz_traces.tag_attributes_v2` | `20260818` | 978 |
| `signoz_traces.top_level_operations` | `all` | 127 |
| 합계 | 대상 6개 파티션 | 10,258,791 |

- 당시 각 테이블의 replica는 1개였고 readonly/session-expired는 `0`이었다. 정상 데이터가 남아 있는 파티션이므로 파티션 전체 삭제를 선택하지 않았다. `top_level_operations`의 `all`은 해당 테이블 전체 데이터 범위다.
- SigNoZ와 ingester를 정지하고 대상 테이블의 merges를 일시 정지했다. 정상 파트 복사본과 기존 detached 항목을 분리한 뒤 파티션별 `DETACH → ATTACH`를 수행했다. ZooKeeper 노드·`GET_PART` 대기열 직접 삭제, 누락 파트 복원은 하지 않았다.
- 쓰기·merges가 정지된 상태에서 대상 파티션별 총 행 수와 `rows > 0`인 파트의 `(rows, bytes_on_disk, hash_of_all_files)` 목록이 전후 일치했다. `CHECK TABLE`은 6개 모두 `1`이었다. 합계는 남아 있던 정상 데이터의 검증값이며, 과거 유실량이나 중단 구간의 수집 누락량을 뜻하지 않는다.
- 중간 검증 스크립트가 `CHECK TABLE` 상세 출력(파트별 행)을 단일 값 `1`로 가정하는 버그로 중단됐다. `check_query_single_value_result=1`을 명시해 이어서 검증했다. 서버 기록상 정지 요청은 17:45:05, 서비스 재시작은 19:58:35–36, Collector ready는 19:58:50(KST)였다. 단시간 중단으로 기록하지 않는다. 이 구간의 실제 수집 누락량은 미확인이다.
- merges와 기존 서비스를 재개했다. ClickHouse·ZooKeeper 컨테이너 ID/시작 시각과 204 override hash는 유지됐다. 배포 설정은 변경하지 않았다.
- 20:00:44(KST) 최종 조회: 전체 복제 대기열 `0`, 대기열 오류 `0`, readonly/session-expired replica `0`, 최대 복제 지연 `0`. 재시작 이후 `NO_REPLICA_HAS_PART` 반복 로그도 `0`이었다. 이는 해당 관찰 구간의 결과이며 향후 재발이 없다는 보장은 아니다.
- 최종 최근 2분 적재: `system.cpu.time` 288건, `system.memory.usage` 168건, `system.network.io` 184건, 트레이스 30건. SigNoZ API `ok`, Collector `Server available`을 확인했다. 로그·메트릭·트레이스 유입은 구분해서 판정한다.
- 당시 만든 보관본은 위 2026-09-09 삭제 이력대로 제거됐다. 재사용 가능한 백업 경로로 안내하지 않는다. 재발 시의 확인·판정 기준은 [저장소 운영 런북](CLICKHOUSE_DATA_STORAGE_RUNBOOK.md)을 따른다.

## 2026-09-08 100.204 추가 배포

- 203 배포 후 사용자의 추가 승인으로 204에도 SigNoZ `v0.140.0`, Collector / migrator `v0.144.9`를 적용했다. 두 서버의 이미지 RepoDigest와 amd64 RootFS 레이어가 동일하다.
- 204의 `/app/signoz`는 작업 브랜치 `codex/upgrade-signoz-v0.140.0`의 커밋 `1171a6dc3c`에서 공식 Foundry 산출물을 재생성하여 배포했다. 기존 미커밋 SQLite·ZooKeeper bind mount 변경은 서버 Git stash와 아래 보관 디렉토리의 patch로 보존했다.
- 204 전용 `/app/signoz-runtime/docker-compose.204.override.yaml`은 변경 전후 바이트 단위로 동일하다. 해당 파일에는 인증값이 있으므로 내용을 출력하지 않고 hash·비교 결과로 검증한다.
- 변경 전 Foundry 파일·override·Compose·스키마 및 정지 상태의 SQLite 보관 경로: `/app/signoz-runtime/upgrade-v0.140.0-MfHPCQNv` (root 전용). ClickHouse 전체 데이터 백업은 아니다.
- 기존 SigNoZ·Collector를 정지하고 SQLite를 복사한 뒤 migrator를 실행했다. migrator 종료 코드 `0`, 로그 `2001`/`2002` 및 트레이스 `1014` 상태 `finished`, SQLite `118`/`119` 적용을 확인했다.
- SigNoZ API 버전 `v0.140.0`, API health `ok`, Collector health `Server available`을 확인했다. SigNoZ·Collector restart count는 `0`이다.
- 실제 신규 메트릭·트레이스 적재와 트레이스의 `inserted_at`/`created_at` 기록을 확인했다. 확인 당시 Collector 전송 실패·수신 거부 지표 9개가 모두 `0`이었다. 최근 5분 로그 유입은 `0`건이므로 새 로그의 실적재는 미확인이다.
- 기존 ClickHouse 테이블 133개의 엔진·키와 View 정의는 유지됐고 메타데이터 테이블 2개가 추가됐다. 삭제된 테이블과 미완료 mutation은 `0`이다.
- SQLite `quick_check`는 `ok`, organization은 기존 1개가 유지됐다. dashboard는 기존 0개에서 신규 시스템 대시보드 1개로 변경됐다.
- ClickHouse·ZooKeeper는 기존 컨테이너 ID와 시작 시각을 유지하며 healthy다. `/data`의 세 bind mount와 ingester/OpAMP/ClickHouse 설정 hash, `sayis`의 metrics/traces SELECT 권한을 유지했다. JSON body 기능은 활성화하지 않았다.
- 기동 중 OpAMP 연결 재시도는 이후 연결 성공으로 회복됐다. SigNoZ 기동 시 active-query 로그 디렉토리 생성 및 license 조회 ERROR가 각각 1건 있었고, 후속 확인 시 두 서비스의 최근 2분 ERROR는 `0`건이었다. 해당 설정을 임의 변경하지 않았다.
- 배포 직후 발견한 기존 문제: 2026-08-18 생성된 `GET_PART` 6건이 `NO_REPLICA_HAS_PART`로 남아 있었다. 업그레이드 단계에서는 변경하지 않았고, 이후 별도 승인으로 위 복제 오류 정리를 완료했다. 현재 미처리 항목으로 해석하지 않는다.

## 2026-09-08 100.203 최초 배포 이력

- 최초 배포 단계의 작업 대상은 `100.203`만이며, 당시 `100.204`는 접속·변경하지 않았다. 이후 204 추가 배포는 위 항목을 따른다. 아래 공통 기준은 2026-09-01에 확인한 이력이다.
- SigNoZ: `v0.139.0` → `v0.140.0`
- Collector / telemetrystore migrator: `v0.144.6` → `v0.144.9`
- ClickHouse `25.12.5`, ZooKeeper `3.7.1`, foundryctl `v0.2.17`은 유지했다. ClickHouse와 ZooKeeper는 기존 컨테이너를 재시작하지 않았다.
- `codex/upgrade-signoz-v0.140.0` 작업 브랜치의 casting으로 공식 `foundryctl forge --no-updater --no-ledger`를 실행했다. 최초 배포 단계에서는 `main` 병합과 204 배포를 수행하지 않았다.
- 기존 ingester와 SigNoZ를 정지하고 SQLite를 복사한 뒤, migrator를 실행하여 종료 코드 `0`을 확인하고 새 ingester와 SigNoZ를 기동했다.
- 변경 전 Foundry 파일·Compose·스키마와 정지 상태의 SQLite 보관 경로: `/app/signoz-runtime/upgrade-v0.140.0-8aMLnrmT` (root 전용). ClickHouse 전체 데이터 백업은 아니다.
- ClickHouse 로그 마이그레이션 `2001`, `2002`와 트레이스 마이그레이션 `1014`가 `finished`이며, SQLite 마이그레이션 `118`, `119`도 반영됐다.
- 기존 ClickHouse 테이블 133개의 engine/sorting/partition/primary key와 View 생성 SQL은 동일하다. `signoz_metadata.field_keys`와 `distributed_field_keys`가 추가됐고, 로그·트레이스 테이블 4개의 DDL은 새 컬럼·인덱스·설정 추가로 변경됐다. 삭제된 테이블은 없다.
- SigNoZ API 버전 `v0.140.0`, API health `ok`, SigNoZ·ClickHouse·ZooKeeper Docker health `healthy`, Collector health `Server available`을 확인했다.
- 실제 로그·트레이스·메트릭의 신규 적재와 로그·트레이스의 `inserted_at`/`created_at` 기록을 확인했다. Collector 전송 실패·수신 거부 지표 13개는 모두 `0`이고, 확인 시점 최근 5분의 SigNoZ·Collector ERROR 로그는 `0`건이었다.
- SQLite `quick_check`는 `ok`이고 기존 대시보드 13개가 모두 유지됐다. 신규 시스템 대시보드 1개가 추가되어 전체 대시보드는 14개다.
- `/data/sayit-clickhouse`, `/data/sayit-sqlite`, `/data/sayit-zookeeper` bind mount와 네트워크·포트·ingester/OpAMP/ClickHouse 설정은 유지했다. `sayis`의 metrics/traces SELECT 권한도 동일하다. JSON body 기능은 새로 활성화하지 않았다.

## 2026-09-01 양쪽 서버 공통 배포 기준 이력

이 절의 이미지 버전·사용 상태는 9월 1일 이력이다. 이후 배포 버전은 문서 상단의 최종 확인 요약과 `casting.yaml`을 기준으로 확인한다.

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

## 업그레이드 조회와 승인 후 준비

### 조회 단계 — 배포하지 않음

`gomdobi/signoz`의 `origin/main:deploy/foundry/casting.yaml` 버전과 upstream 최신 정식 릴리즈를 먼저 비교한다. RC·개발 브랜치는 대상에서 제외한다. 업그레이드 대상이면 공식 릴리즈 노트에서 Collector·migrator·ClickHouse·ZooKeeper·Foundry 변경을 우선 확인한다. 단순 조회 지시를 서버 접속, 파일 재생성, 배포나 `main` 병합 승인으로 확대하지 않는다.

```bash
git fetch origin main
git show origin/main:deploy/foundry/casting.yaml | grep -nE 'image: (signoz/signoz:|signoz/signoz-otel-collector:)'
git ls-remote --tags --sort='version:refname' upstream 'refs/tags/v*' \
  | grep -E 'refs/tags/v[0-9]+\.[0-9]+\.[0-9]+$' | tail -n 1
```

태그 조회값은 후보 확인용이다. [SigNoZ 공식 Releases](https://github.com/SigNoz/signoz/releases)에서 실제 정식 발행 여부와 릴리즈 노트를 확인한 뒤 업그레이드 대상으로 보고한다.

### 승인 후 준비

대상 서버와 변경 범위를 승인받은 뒤 아래 준비를 진행한다. 203 승인을 204 승인으로 해석하지 않는다. 저장소 `main` 반영도 별도 명시적 지시를 따른다.

1. 전용 작업 브랜치에서 `casting.yaml`을 수정하고 Foundry 산출물을 생성·검증한다.

```bash
foundryctl forge --no-updater --no-ledger -f deploy/foundry/casting.yaml -p deploy/foundry/pours
docker compose -f deploy/foundry/pours/deployment/compose.yaml config --quiet
```

`foundryctl forge`가 실패하면 기존 `pours`를 배포하지 않는다. 특히 ClickHouse mount의 JSON Patch `test` 실패는 upstream 생성 구조가 달라졌다는 의미이므로 `casting.yaml`과 새 생성물을 먼저 비교한다.

2. 커스텀 유지 여부를 확인한다.

```bash
grep -nE 'signoz/signoz:v|signoz-otel-collector:v|clickhouse/clickhouse-server:|signoz/zookeeper:|9000:9000|8123:8123|9181:9181|8889:8889|uptime_kuma_api_key|/data/sayit-clickhouse:/var/lib/clickhouse' deploy/foundry/pours/deployment/compose.yaml
grep -nE 'job_name: uptime-kuma|password_file: /app/secrets/uptime_kuma_api_key|endpoint: 0.0.0.0:8889|prometheus' deploy/foundry/pours/deployment/ingester/ingester.yaml
grep -nE 'replica: example01-01-1|shard: "01"|sayis:|GRANT SELECT ON signoz_(metrics|traces)\.\*' deploy/foundry/pours/deployment/telemetrystore/clickhouse/config-0-0.yaml
test "$(grep -Fc '/data/sayit-clickhouse:/var/lib/clickhouse' deploy/foundry/pours/deployment/compose.yaml)" -eq 1
! grep -qE 'signoz-clickhouse|signoz-telemetrystore-0-0-data:/var/lib/clickhouse' deploy/foundry/pours/deployment/compose.yaml
```

3. `sayis-dashboard-api`에 영향을 줄 수 있는 ClickHouse 구조 변경을 확인한다.

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

승인된 대상 서버의 `/app/signoz`를 승인된 배포 커밋과 일치시킨 뒤 공식 Foundry 산출물을 생성하고 검증한다. 실제 2026-09-08 배포는 작업 브랜치의 `1171a6dc3c`를 사용했다. `git pull origin main`만으로 현재 브랜치가 `main`으로 바뀌는 것은 아니므로, 현재 브랜치·미커밋 변경·승인 커밋을 먼저 확인한다. 코드 동기화는 이 확인 후 승인 범위에서 수행하며, 아래 예시는 동기화 완료 후 검증·생성 단계다.

SSH는 `~/.ssh/config`와 Include 대상에서 별칭을 확인하고 `ssh -G net100-203` 또는 `ssh -G net100-204`의 실제 적용값을 검증한 뒤 사용한다. 서버 Docker 제어는 `gomdobi`의 승인된 sudo 경로를 사용하며 Docker 그룹·소켓 권한을 변경하지 않는다.

`/data`가 실제 LVM 파일시스템으로 mount되지 않은 상태에서 Compose를 기동하면 안 된다. Docker가 호스트 루트 파일시스템에 같은 경로를 만들 수 있으므로 `findmnt` 결과를 먼저 고정 검증한다.

```bash
cd /app/signoz
test "$(findmnt -n -o TARGET -T /data/sayit-clickhouse)" = "/data"
test "$(findmnt -n -o SOURCE -T /data/sayit-clickhouse)" = "/dev/mapper/vg_data-lv_data"
test "$(findmnt -n -o TARGET -T /data/sayit-sqlite)" = "/data"
test "$(findmnt -n -o TARGET -T /data/sayit-zookeeper)" = "/data"
sudo git status --short --branch
sudo git --no-pager log -1 --oneline
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

실제로 배포 승인된 서버에서 실행한다. 이 목록을 이유로 다른 서버까지 접속하거나 변경하지 않는다.

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
  clickhouse-client --query "SELECT count() AS queue_total, countIf(last_exception != '') AS queue_errors FROM system.replication_queue"
sudo docker exec signoz-telemetrystore-clickhouse-0-0 \
  clickhouse-client --query "SELECT database, table, queue_size, is_readonly, is_session_expired, absolute_delay FROM system.replicas ORDER BY database, table"
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
- 복제 대기열 건수만으로 장애를 단정하지 않는다. 정상 `MERGE_PARTS`와 같은 일시적 작업과 반복 실패를 구분하고, 예외·재시도 증가·지연을 함께 확인한다. 재발 진단은 저장소 운영 런북을 따른다.
- 최신 metrics write 시각이 현재 시각으로 계속 갱신되어야 한다. 로그 유입 `0`건을 Infrastructure 메트릭 유입 없음으로 표현하지 않는다.
- Collector는 Docker healthcheck가 없을 수 있다. 컨테이너 `running`만으로 완료 판정하지 않고 health endpoint, 전송 실패·수신 거부 지표와 실제 신규 적재를 확인한다.
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
