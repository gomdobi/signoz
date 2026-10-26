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

## 반복 업그레이드 고정 절차

매번 새 절차나 별도 시험 환경을 만들지 않고 아래 순서를 재사용한다. 대상·버전만 승인된 값으로 바꾼다. 추가 시험과 성능 측정은 별도 요청이 있을 때만 수행한다.

사용자 지시 기준: 추가·변경 사항은 SigNoZ 공식 최신 구성을 따른다. 기존 설정 유지나 선택 기능이라는 자체 판단으로 공식 변경을 제외하지 않는다. 이미지/마이그레이션뿐 아니라 공식 생성 설정과 OpAMP가 실제 전달한 런타임 설정까지 비교해 변경·적용 여부를 기록한다. 기존 사용자 승인 커스텀과 충돌하면 숨기거나 임의 결정하지 않고 차이와 영향을 보고한다.

1. 공식 릴리즈와 기존 casting/실행 버전을 비교한다. SSH 별칭·적용값, Git 변경 상태, `/data` mount를 확인한다.
   - 2026-09-28 별도 승인으로 203·204 모두 ClickHouse Keeper로 전환했다. 204 전용 override도 Keeper 서비스명을 사용하며, 과거 ZooKeeper casting으로 덮어쓰지 않는다.
2. 기존 변경을 보존하고 이번 작업 브랜치에서 casting 버전 및 공식 업그레이드 가이드가 요구하는 설정을 반영한다. 변경 전 Foundry 파일·유효 Compose·Git patch·컨테이너 상태를 root 전용 `/app/signoz-runtime/upgrade-<버전>-XXXXXX`에 보관한다. 204 override도 보관한다.
3. 이미지를 미리 pull하고 기존 Foundry 명령으로 재생성한다. 유효 Compose와 생성 설정에서 승인된 이미지·필수 설정 외 변경이 있으면 배포하지 않는다. Foundry 갱신이 필요하면 기존 바이너리를 보관하고 공식 설치 스크립트의 버전·경로를 명시한다.
4. `ingester`와 `signoz-signoz-0`을 정지하고 `/data/sayit-sqlite`를 보관한다. SQLite `PRAGMA quick_check`를 확인한다.
5. SigNoZ만 변경되면 migrator를 재실행하지 않는다. Collector/migrator가 변경되면 공식 migrator를 재생성하고 종료 코드 `0`을 확인한다. 실패하면 후속 기동을 중단하고 오류를 보고한다.
6. `signoz-signoz-0`과 `ingester`를 기동한다. ClickHouse·Keeper/ZooKeeper는 변경 대상으로 승인되지 않는 한 재생성하거나 재시작하지 않는다.
7. 버전·health·재시작 횟수·실제 메트릭/트레이스 유입과 기존 mount·204 override 유지 여부만 확인하고 결과를 기록한다. 커밋·푸시·병합은 별도 지시에 따른다.

원격 명령은 승인된 sudo 셸에서 아래 Compose 배열을 공통으로 사용한다. `git`과 `foundryctl`도 기존 root 소유 `/app/signoz`에서 실행하며, 매번 실행 계정이나 인증 방식을 바꾸지 않는다.

```bash
cd /app/signoz
dc=(docker compose --ansi never --progress plain -f /app/signoz/deploy/foundry/pours/deployment/compose.yaml)
# 204에서만 추가
# dc+=(-f /app/signoz-runtime/docker-compose.204.override.yaml)
/usr/local/bin/foundryctl --no-ledger --no-updater forge \
  -f /app/signoz/deploy/foundry/casting.yaml -p /app/signoz/deploy/foundry/pours
"${dc[@]}" config --quiet
# 변경 전후 설정 비교와 이미지 pull 완료 후
"${dc[@]}" stop ingester signoz-signoz-0
# SQLite 복사 및 quick_check 완료 후, Collector 변경 시에만:
# "${dc[@]}" up -d --no-deps --force-recreate --pull never signoz-telemetrystore-migrator
# test "$(docker wait signoz-telemetrystore-migrator)" = 0
"${dc[@]}" up -d --no-deps --pull never signoz-signoz-0 ingester
```

아래 날짜별 기록은 과거 실행 증거이며 새로운 절차로 해석하지 않는다. 아래 전체 스택 배포 예시는 최초 설치용이며 반복 업그레이드에는 위 선택적 기동 절차를 사용한다.

## 최종 확인 요약

- 2026-10-26 배포 확인: 203·204 모두 SigNoZ `v0.147.0`, Collector / migrator `v0.144.15`다. foundryctl `v0.3.0`, ClickHouse / ClickHouse Keeper `25.12.5`, SQLite 및 기존 `/data` bind mount는 유지했다.
- 이번 작업 브랜치는 로컬 `codex/upgrade-signoz-v0.147.0-20261026`, 서버 각각 `codex/upgrade-signoz-v0.147.0-203-20261026`, `codex/upgrade-signoz-v0.147.0-204-20261026`다. 기존 미커밋 변경을 보존했다. 사용자가 이번 로컬 작업의 커밋과 `main` 병합을 별도로 승인했다. 원격 푸시는 별도 지시 후 수행하며, 과거 작업의 Git 승인을 이번 작업에 재사용하지 않는다.
- `sayis`는 기존 사용자 승인대로 `default`와 동일한 권한을 유지한다. 양쪽 실제 `SHOW GRANTS`의 동등성과 배포 전후 불변을 확인했다. 오래된 SELECT 전용 문구·casting을 현재 운영 정책에 맞췄으며, 서버의 활성 ClickHouse 설정과 권한은 변경하지 않았다.
- 204의 기존 복제 오류 6건은 2026-09-08 별도 승인 작업으로 정리됐다. 2026-09-09에는 해당 작업 보관본 107MB만 사용자 지시로 영구 삭제했다.
- 아래 수치와 상태는 각 작업 당시 실행 결과다. 문서 갱신 자체를 서버 재검증이나 재배포로 보지 않는다.

## 2026-10-26 203·204 Docker 업그레이드

- 기존 고정 절차로 실제 서버의 SigNoZ `v0.145.0` → `v0.147.0`, Collector / migrator `v0.144.13` → `v0.144.15`를 적용했다. 로컬 main에 있던 Collector `v0.144.14`는 10월 14일 번들용 소스 반영이며 당시 서버 배포는 하지 않았다.
- 공식 릴리즈: https://github.com/SigNoz/signoz/releases/tag/v0.147.0 및 https://github.com/SigNoz/signoz-otel-collector/releases/tag/v0.144.15. Collector 핵심 변경은 로그·트레이스 JSON 직렬화의 비유한 수/범위/중첩 처리, NaN 메트릭 계량 제외, histogram의 `+Inf` 버킷 계량 교정이다. 공식 최신 Foundry 릴리즈 `v0.3.0`의 해당 수집 템플릿은 logs processor를 `[batch]`로 생성하며 양쪽도 동일하다. `signozlogsnormalizer`를 자체 판단으로 제외한 결과가 아니라 현재 공식 기본 생성값과의 대조 결과다. 근거: https://github.com/SigNoz/foundry/blob/v0.3.0/internal/molding/ingestermolding/templates/config.v01446.yaml.gotmpl.
- root 전용 변경 전 보관본: 203 `/app/signoz-runtime/upgrade-v0.147.0-rYt18q`, 204 `/app/signoz-runtime/upgrade-v0.147.0-bGKe8N`. Foundry·바이너리·유효 Compose·Git patch·컨테이너 상태·실제 Collector 설정·권한·replica 경로·테이블 UUID/engine, 정지 상태 SQLite 전체 복사본과 실행 로그를 보관했다. 204 override도 포함한다. SQLite 원본/복사본 파일 해시 일치와 `quick_check=ok`를 확인했다. ClickHouse 전체 데이터 백업은 아니다.
- 공식 Collector migrator는 양쪽 종료 코드 `0`이다. SigNoZ 시작 시 SQLite 마이그레이션 133–137번이 적용된 것을 migration 테이블로 확인했다. 이는 순서 번호이며 각각 rule_view 추가, 로그·트레이스 필드 권한 추가, 자동 동기화 LLM 가격 규칙 정리, Telegram 채널 v2 사양 보완, 메트릭 필드/관리 역할 권한 갱신이다. 이들 `Down`은 DB 원복을 구현하지 않으므로 이미지 교체만으로 SQLite를 원복할 수 없다.
- 실제 유효 Compose 변경은 SigNoZ·Collector·migrator의 세 이미지뿐이다. ingester·OpAMP·Keeper·ClickHouse functions 생성물과 204 override는 동일하다. 양쪽 ClickHouse·Keeper 및 나머지 기존 서비스의 ID/시작 시각/재시작 횟수와 mount를 유지했다. mount 비교는 Docker가 반환한 배열 순서가 아닌 destination별 실제 속성으로 수행했다.
- 실제 Collector 설정은 배포 파일과 구분해 비교했다. 새 SigNoZ의 공식 OpAMP GenAI 규칙이 적용되어 `signozspanmapper`는 변경됐다. `gen_ai.llm` 정의 v4의 mapper 13개, `gen_ai.agent` 정의 v3의 5개, `gen_ai.tool` 정의 v3의 6개와 모든 공식 source가 양쪽 SQLite·실제 Collector에서 활성 상태임을 공식 v0.147.0 JSON 정의와 직접 대조했다. operation·tool·추론/캐시 토큰·finish reason·session·agent 속성의 새 매핑을 포함한다. 나머지 설정 차이는 telemetry의 실행 instance UUID 제거뿐이다. 생성 파일이 같다는 이유로 실제 수집 설정까지 동일하다고 보고하지 않는다. 공식 정의: https://github.com/SigNoz/signoz/tree/v0.147.0/pkg/modules/spanmapper/implspanmapper/fs/definitions.
- 위 mapper 24개는 기존 규칙을 포함한 최신 정의의 총수이며 이번에 24개 전부가 추가됐다는 뜻이 아니다. 서로 다른 AI 계측 도구의 모델·제공자·토큰·대화·Agent·Tool 속성을 공통 `gen_ai.*` 키로 맞춰 조회·집계하는 규칙이다. AI 실행 환경 설치나 기존 데이터 일괄 변환 작업은 아니다.
- `sayis`의 기존 `default` 동등 권한은 변경하지 않았다. casting에 남은 SELECT 전용 정의를 기존 활성 설정의 네 권한 플래그(`access_management`, `named_collection_control`, `show_named_collection`, `show_named_collection_secrets` 모두 `1`)로 동기화했다. 재생성한 ClickHouse 설정은 필드 순서를 제외하면 기존 활성 설정과 같고 암호도 동일하다. 활성 설정 파일은 바이트 단위로 보존해 ClickHouse 재시작/설정 변경을 하지 않았다. 로컬·203·204 casting SHA-256은 `ec8faf3fe905e438782ba6c0b7fefcb2277ba584ebf1e6235e87e0c3c5a2c731`이다.
- 정지 요청 시각(KST)은 203 `13:26:06`, 204 `13:31:08`이다. 기존 Collector는 양쪽 10초 대기 후 종료 코드 `137`, `OOMKilled=false`로 정지됐다. 기존 SigNoZ 종료 코드는 203 `1`(원인 미확인), 204 `0`이다. 203을 정상 종료로 기록하지 않는다. 정지 구간의 실제 수집 누락량은 미확인이다.
- 203은 준비 상태 스크립트가 health 응답의 `Server available` 문구를 로그에서 찾는 버그로 대기했다. 새 Collector 로그의 `Everything is ready`와 공식 health HTTP 응답을 직접 확인하고 추가 재시작 없이 검증을 이어갔다. Collector 기동 준비 로그는 `13:26:36`, health 재확인 기록은 `13:29:56`이며 후자를 실제 서비스 중단 시간으로 해석하지 않는다. 204 health 확인은 `13:31:34`다.
- 실행 후 검증: 양쪽 API `v0.147.0`·health `ok`, Collector health `Server available`, 새 SigNoZ·Collector 재시작 횟수 `0`, SQLite `quick_check=ok`다. 기존 테이블 UUID/engine과 replica 경로/replica명이 동일하다. 복제 readonly·session expired·대기열·대기열 오류·최대 지연은 양쪽 모두 `0`이다.
- 최종 관찰 시각(KST): 203 `13:31:02`, 204 `13:32:27`. health 확인 이후 실제 신규 적재는 203 메트릭 `300,216` / 트레이스 `539`건, 204 메트릭 `16,323` / 트레이스 `14`건이다. Collector 메트릭·트레이스 수신 거부 및 전송 실패는 모두 `0`이다. 203 로그 관련 카운터도 `0`; 204에는 해당 로그 시계열이 없어 로그 유입 성공을 주장하지 않는다. 별도 부하·성능 시험이나 테스트 데이터 주입은 하지 않았다.
- 같은 관찰 구간의 Collector ERROR는 양쪽 `0`, SigNoZ ERROR는 203 `0`, 204 `failed to get active license` 1건이다. 후자는 활성 라이선스 조회 오류이며 API·수집 정상 여부와 구분한다. 시작 과정의 OpAMP 연결 재시도와 active-query 로그 디렉토리 생성 오류도 관찰했으므로 전체 로그가 무오류였다고 보고하지 않는다.

## 2026-10-12 203·204 Collector 공식값 교정

- 사용자 승인으로 공식 Foundry `v0.3.0` 수집 템플릿과 다른 기존 설정 4개를 교정했다. 일반 batch는 `send_batch_size=50000`, `send_batch_max_size=55000`, `timeout=5s`; 계량 batch timeout은 `5s`; 로그 exporter timeout은 `45s`; 활성 health 확장은 `signoz_health_check`다. 비활성으로 남아 있던 기존 `health_check` 정의도 제거했다.
- 공식 근거: https://github.com/SigNoz/foundry/blob/v0.3.0/internal/molding/ingestermolding/templates/config.v01446.yaml.gotmpl. 이는 승인된 네 항목을 공식값으로 맞춘 작업이며 모든 사용자 정의 설정을 제거하거나 모든 신규 기능을 활성화한 작업으로 해석하지 않는다.
- root 전용 변경 전 보관본: 203 `/app/signoz-runtime/collector-defaults-20261012-fZCwEQ`, 204 `/app/signoz-runtime/collector-defaults-20261012-8vuZuN`. Foundry 파일·Git patch·유효 Compose·기존 실제 수집 설정·컨테이너 상태·실행 로그를 보관했으며 204 override도 포함했다. 데이터 마이그레이션이나 DB 복사는 수행하지 않았다.
- 로컬·서버 모두 동일한 Foundry `v0.3.0`으로 forge했다. 생성 설정을 구조 비교해 네 항목만 바뀌었음을 확인했고 다른 생성 파일·유효 Compose·204 override는 동일했다. casting SHA-256은 `b9a0d1e1d0fad19dcd597ebddd3b2ddb5561a7ea2d16227564d37ec64cefcaae`, 생성 ingester 설정은 `aa5400a96a1e3066edbbd9a7cda729e714c12e2116dc8cbf8fad2b38658339cd`로 로컬·양쪽 서버가 일치했다.
- Collector만 순차적으로 정지하고 `up -d --no-deps --force-recreate --pull never ingester`로 재생성했다. SigNoZ·ClickHouse·Keeper·sayis-dashboard-api의 컨테이너 ID/시작 시각/재시작 횟수는 전후 동일했다. 이미지·스키마는 변경하지 않았고 migrator도 재실행하지 않았다.
- 정지 요청 → 공식 health 응답(KST): 203 `11:33:48 → 11:35:21`(93초), 204 `11:37:21 → 11:38:55`(94초). 양쪽 기존 Collector는 90초 대기 후 강제 종료돼 종료 코드 `137`을 남겼고 `OOMKilled=false`였다. 정지 구간의 실제 수집 누락량은 미확인이다.
- 203의 재기동 후 최초 실제 설정 비교는 자동 생성된 `service.telemetry.resource.service.instance.id` 때문에 중단됐다. 공식 Collector `opamp/config_manager.go`의 `UpsertInstanceID`가 생성하는 UUID임을 확인했다. 이 런타임 식별자만 구분하고 나머지 설정 전체를 비교해 네 교정 항목 외 변경이 없음을 검증했다. 추가 재시작은 하지 않았다.
- 최종 조회(KST): 203 `11:37:14`, 204 `11:39:04`. 실제 `/var/tmp/collector-config.yaml`에서 네 공식값을 확인했다. 새 Collector 재시작 횟수 `0`, ready 이후 ERROR `0`, 메트릭·트레이스 수신 거부/전송 실패 모두 `0`이었다. 203 로그 관련 거부/실패도 `0`; 204는 로그 관련 카운터 시계열이 없어 로그 유입 성공을 주장하지 않는다. health 응답 이후 신규 실적재는 203 메트릭 577,287 / 트레이스 996건, 204 메트릭 1,857 / 트레이스 1건이었다. 복제 readonly·session expired·대기열·대기열 오류는 양쪽 `0`이었다.
- 공식 `signoz_health_check`는 공식 README상 항상 healthy를 반환하는 확장이다. 실제 응답의 `upSince`는 영 시각이어서 가동 시간 근거로 사용하지 않았다. Docker 시작 시각, 실제 데이터 적재와 실패 카운터를 별도로 검증했다. 근거: https://github.com/SigNoz/signoz-otel-collector/blob/v0.144.13/extension/healthcheckextension/README.md.
- 로컬 `git diff --check` 및 Compose 검증은 종료 코드 `0`이었다. 서버 교정 당시에는 커밋·푸시·main 병합을 하지 않았으며, 후속 형상관리 승인 범위는 최종 확인 요약을 따른다.

## 2026-10-12 203·204 Docker 업그레이드

- 기존 고정 절차로 SigNoZ `v0.143.0` → `v0.145.0`, Collector / migrator `v0.144.12` → `v0.144.13`을 적용했다. 공식 Foundry `v0.3.0`은 유지했다. 로컬과 서버의 forge 및 Compose 검증은 종료 코드 `0`이었다.
- 변경 전후 유효 Compose는 위 세 서비스 이미지 외 동일했다. ingester·OpAMP·ClickHouse·Keeper 생성 설정은 바이트 단위로 동일하고, 204 override도 유지했다. 새 `signozlogsnormalizer` 프로세서는 현재 pipeline에 추가하지 않았다. ClickHouse·Keeper·sayis-dashboard-api의 컨테이너 ID/시작 시각/재시작 횟수는 전후 동일했다. ZooKeeper는 기존 정지 상태로 유지했다.
- root 전용 보관본: 203 `/app/signoz-runtime/upgrade-v0.145.0-XzHWFY`, 204 `/app/signoz-runtime/upgrade-v0.145.0-sYCvQs`. 변경 전 Foundry·바이너리·유효 Compose·Git patch·컨테이너 상태, 정지 상태 SQLite 복사본, 스키마·replica 경로·sayis 권한 비교 자료와 실행 로그를 보관했다. 204 override도 포함했다. 양쪽 SQLite 원본/복사본 일치 및 `quick_check=ok`를 확인했다. ClickHouse 전체 데이터 백업은 아니며 이미지 교체만으로 DB 원복을 보장하지 않는다.
- Collector 변경으로 공식 migrator를 재생성했다. 양쪽 종료 코드 `0`, 트레이스 로컬 테이블 `signoz_index_v3`의 bloom_filter 인덱스 4개(`idx_attributes_http_route`, `idx_attributes_rpc_method`, `idx_attributes_gen_ai_request_model`, `idx_attributes_gen_ai_provider_name`) 및 traces JSON 컬럼 진화 메타데이터 1개를 확인했다. 기존 테이블 135개의 UUID/engine/key, 복제 테이블의 coordination 경로·replica명, sayis 권한은 유지됐다.
- 정지 요청 → SigNoZ·Collector health 확인(KST): 203 `10:32:04 → 10:36:07`(4분 3초), 204 `10:36:41 → 10:38:38`(1분 57초). 정지 구간의 실제 수집 누락량은 미확인이다. 양쪽 Collector는 90초 종료 대기 후 강제 종료되어 종료 코드 `137`을 남겼다. 204 구버전 SigNoZ는 SIGTERM 후 종료 코드 `1`을 남겼으며 그 원인은 미확인이다. 정상 종료로 기록하지 않는다.
- 203은 임시 검증 스크립트가 SQLite `quick_check` 이후 디렉토리를 비교하는 순서 버그로 중단됐다. 백업 조회가 만든 0-byte WAL과 32,768-byte SHM만 추가됐고 원본/백업 DB SHA-256은 동일했다. 실제 데이터 차이는 없었다. 원본 파일 일치와 보조 파일 상태를 확인하고, 비교를 조회보다 먼저 수행하도록 임시 검증 순서를 바로잡아 동일 보관본에서 이어서 배포했다. 이 중단이 위 203 정지 시간에 포함된다.
- 최종 조회(KST): 203 `10:37:45`, 204 `10:39:51`. 양쪽 API 버전 `v0.145.0`, API health `ok`, SigNoZ·ClickHouse·Keeper·sayis-dashboard-api `healthy`, Collector `Server available`, 새 SigNoZ·Collector 재시작 횟수 `0`이었다. ready 이후 SigNoZ·Collector ERROR는 양쪽 `0`이었다.
- health 확인 이후 실적재는 203 메트릭 528,790 / 트레이스 1,093건, 204 메트릭 9,009 / 트레이스 19건이었다. Collector 메트릭·트레이스 수신 거부 및 전송 실패 카운터는 양쪽 모두 `0`이었다. 203의 로그 관련 카운터도 `0`; 204는 해당 로그 카운터 시계열이 없어 로그 유입 성공을 주장하지 않는다. 별도 성능 시험은 수행하지 않았다.
- 복제 테이블 및 Keeper 기존 경로는 203 12개 / 204 56개다. readonly·session expired·복제 대기열·대기열 오류·최대 복제 지연·미완료 mutation은 양쪽 모두 `0`이었다.
- `/dev/mapper/vg_data-lv_data`의 ext4 `/data` mount와 `/data/sayit-clickhouse`, `/data/sayit-sqlite`, `/data/sayit-clickhouse-keeper`의 실제 bind mount를 확인했다. Keeper 이미지의 선언으로 생성된 `/var/lib/clickhouse` 익명 볼륨은 양쪽 모두 비어 있었다(디렉토리 할당 4KiB). 실제 Keeper log/snapshot 경로는 `/var/lib/clickhouse-keeper/coordination/{log,snapshots}`로 `/data` bind 안에 있다. 익명 볼륨을 삭제하거나 저장 설정을 변경하지 않았다.
- 공식 릴리즈: https://github.com/SigNoz/signoz/releases/tag/v0.145.0 및 https://github.com/SigNoz/signoz-otel-collector/releases/tag/v0.144.13. 설정 교정이나 추가 기능 활성화 없이 기존 배포 방식을 유지했다.

## 2026-09-28 204 ZooKeeper → ClickHouse Keeper 전환

- 203 전환 후 사용자의 추가 지시로 204도 같은 공식 변환 절차를 적용했다. 기존 Foundry `v0.3.0`으로 ClickHouse Keeper `25.12.5` 설정을 생성했으며, ClickHouse·SigNoZ·Collector 이미지는 유지하고 migrator는 재실행하지 않았다. 이 후속 작업에서 203 서버는 변경하지 않았다.
- 영구 경로는 `/data/sayit-clickhouse-keeper:/var/lib/clickhouse-keeper`, ClickHouse coordination endpoint는 `signoz-telemetrykeeper-clickhousekeeper-0:9181`이다. Keeper 클라이언트/Raft 포트는 호스트에 공개하지 않았다. `/data`의 `vg_data/lv_data` ext4 mount는 그대로 유지했다.
- root 전용 보관본: `/app/signoz-runtime/keeper-migration-204-NR33Uf`. 변경 전 Foundry·Git patch·유효 Compose·컨테이너 상태·204 override, 정지 상태 SQLite·ZooKeeper 복사본, 변환 스냅샷, 스키마·UUID·replica 경로·권한·행 수 비교 자료를 보관했다. SQLite `quick_check=ok`, 정지 상태 ZooKeeper 복사본과 원본 대조가 성공했다. ClickHouse 전체 데이터 백업은 아니다.
- 204 override는 `signoz-telemetrykeeper-zookeeper-0` 서비스 키만 `signoz-telemetrykeeper-clickhousekeeper-0`으로 바꿨다. 나머지 설정값이 동일함을 구조 비교로 확인했고, 유효 Compose도 Keeper 서비스 교체와 ClickHouse 의존 서비스 변경 외 동일하다. override SHA-256은 `561d286d3bca7b140c04fc29b13aa998e3bc8315bf1fe19a1d2eb3ef5cb1481b` → `6ea3493bb7f1d0cc4b5f9800c63dd017708822ebb699df15229a9e26e4b10844`다.
- 수집·SigNoZ, ClickHouse, ZooKeeper 순으로 정지한 뒤 공식 `keeper-converter`로 변환했다. 결과는 `snapshot_34854180.bin.zstd`(269,613 bytes)이며 Keeper 최초 기동 전에 배치했다. 기존 `/data/sayit-zookeeper`(정지 후 133MB)와 ZooKeeper 컨테이너는 정지 상태로 보존했다. 신규 쓰기가 재개됐으므로 옛 ZooKeeper 단순 재기동으로 원복하지 않는다.
- 정지 요청 `12:43:31` → Keeper 기동 확인 `12:45:14` → SigNoZ·Collector health 확인 `12:45:40`(KST), 총 2분 9초다. Collector는 90초 종료 대기 후 종료 코드 `137`로 정지됐다. 정지 구간의 미수집량은 측정하지 않았다.
- 테이블 135개의 UUID/engine/key, 복제 테이블 56개의 coordination 경로·replica명, sayis 권한이 일치했다. Keeper의 `/clickhouse/tables` 아래 기존 56개 경로가 모두 존재한다. ClickHouse·SigNoZ·Collector의 기존 mount도 그대로 유지됐다.
- 기존 데이터가 있는 테이블 26개 중 24개는 재기동 전후 물리 행 수가 같았다. `signoz_metrics.usage`와 `signoz_traces.usage`는 각각 72 → 71행이며, 기존 3일 TTL과 `system.part_log`의 `TTLDeleteMerge`(각각 71행 읽기, 70행 출력)로 확인했다.
- `12:46:38` 최종 조회: SigNoZ·ClickHouse·Keeper `healthy`, Collector `Server available`, 네 서비스 재시작 횟수 0. readonly·session expired·복제 대기열·대기열 오류·미완료 mutation은 모두 0이다. `12:45:40` 이후 새 CPU 120 / 메모리 78 / 네트워크 88 / 트레이스 15건을 확인했다. ready 이후 ERROR는 네 서비스 모두 0이며 sayis-dashboard-api도 `healthy`다.
- 공통 casting/Compose SHA-256은 203 적용본과 동일하다. 9월 28일 서버 전환 당시에는 커밋·푸시·병합하지 않았으며, 이후 형상관리 승인 범위는 위 최종 확인 요약을 따른다.
- 공식 절차: https://clickhouse.com/docs/guides/oss/deployment-and-scaling/keeper#migration-from-zookeeper

## 2026-09-28 203 ZooKeeper → ClickHouse Keeper 전환

- 대상은 203만이다. 204 서버는 변경하지 않았다. 공식 Foundry `v0.3.0`의 `telemetrykeeper.kind: clickhousekeeper`와 이미지 `clickhouse/clickhouse-keeper:25.12.5`를 사용했다. 기존 ClickHouse·SigNoZ·Collector 이미지와 스키마 버전은 유지했고 migrator를 재실행하지 않았다.
- Keeper 영구 경로는 `/data/sayit-clickhouse-keeper:/var/lib/clickhouse-keeper`다. Keeper 설정은 Foundry 공식 생성 기본값을 사용했다. ClickHouse의 coordination endpoint는 `signoz-telemetrykeeper-clickhousekeeper-0:9181`로 변경했다. 유효 Compose 비교에서 Keeper 서비스 교체와 ClickHouse 의존 서비스 변경만, ClickHouse 설정 비교에서 ZooKeeper 접속 대상 변경만 확인했다.
- root 전용 보관본: `/app/signoz-runtime/keeper-migration-203-iJJ7Qv`. 변경 전 Foundry·Git patch·Compose·컨테이너 상태, 정지 상태 SQLite·ZooKeeper 복사본, 변환 스냅샷, 테이블 UUID/스키마·replica 경로·권한·행 수 비교 자료가 있다. ClickHouse 전체 데이터 백업은 아니다.
- 수집과 SigNoZ를 정지하고 ClickHouse merge·복제 대기열·mutation을 확인한 뒤 ClickHouse와 ZooKeeper를 정지했다. ZooKeeper 데이터 디렉토리 복사본은 원본과 대조했다. 설치된 ClickHouse의 공식 `keeper-converter`로 snapshot·transaction log를 변환했다. 결과는 `snapshot_9797.bin.zstd`(16,086 bytes)이며, Keeper 최초 기동 전에 snapshot 디렉토리에 배치했다.
- 기존 `/data/sayit-zookeeper`와 ZooKeeper 컨테이너는 정지 상태로 보존했다. Keeper에서 신규 쓰기를 재개한 뒤에는 옛 ZooKeeper를 단순 재기동하는 방식으로 원복하지 않는다. 양쪽 coordination 상태의 시점이 달라지므로 별도 복구 판단이 필요하다.
- 정지 요청 `11:51:47` → Keeper 기동 확인 `11:53:49` → SigNoZ·Collector health 확인 `11:54:21`(KST). Collector는 90초 종료 대기 후 종료 코드 `137`로 정지됐고, 정지 중 OpAMP 접속 재시도 로그가 있었다. 정지 구간의 미수집량은 측정하지 않았다. 재기동 이후 Collector는 정상 수집 중이며 최종 검증 구간 ERROR는 0이다.
- 최종 상태: SigNoZ·ClickHouse·Keeper `healthy`, Collector `Server available`, 네 서비스 재시작 횟수 0. 테이블 135개의 UUID/engine/key, 복제 테이블 12개의 ZooKeeper 경로·replica명, sayis 권한과 ClickHouse mount가 일치했다. readonly·session expired·복제 대기열·대기열 오류·미완료 mutation은 모두 0이다. Keeper client에서 `ls '/clickhouse/tables'`로 복제 메타데이터 경로도 확인했다. 경로는 따옴표로 감싸며, client 종료 코드만으로 조회 성공을 판단하지 않는다.
- 기존 데이터가 있는 테이블 35개를 확인했다. 그중 34개는 재기동 전후 물리 행 수가 같았고, `signoz_logs.usage`의 74 → 71행 변경은 `system.part_log`의 `TTLDeleteMerge`(72행 읽기, 69행 출력) 및 기존 3일 TTL로 확인했다.
- `11:55:25` 조회: `11:54:21` 이후 새 CPU 11,060 / 메모리 5,178 / 네트워크 5,576 / 트레이스 724건을 확인했다. SigNoZ·Collector·ClickHouse·Keeper의 ready 이후 ERROR는 모두 0이며, sayis-dashboard-api도 `healthy`다.
- 공식 절차: https://clickhouse.com/docs/guides/oss/deployment-and-scaling/keeper#migration-from-zookeeper

## 2026-09-28 203·204 Docker 업그레이드

- 기존 고정 절차로 SigNoZ `v0.142.1` → `v0.143.0`, Collector / migrator `v0.144.10` → `v0.144.12`를 적용했다. 공식 스크립트 `https://signoz.io/foundry.sh`의 `-v v0.3.0 -d /usr/local/bin -y`로 양쪽 foundryctl을 갱신했다. 체크섬 검증과 설치 후 버전 실행은 공식 스크립트가 수행했다. 기존 바이너리는 아래 보관본에 보존했다.
- casting에 공식 `signozspanmapper`, `signozllmpricing` 정의와 traces pipeline 순서를 반영하고 Foundry `v0.3.0`으로 재생성했다. 유효 Compose는 SigNoZ·Collector·migrator 이미지 세 개만 변경됐고, 생성 설정은 ingester의 위 프로세서 정의·순서 외 바이트 단위로 동일했다. 실제 OpAMP 적용 후 `/var/tmp/collector-config.yaml`의 프로세서 순서도 확인했다.
- 기존 미커밋 변경을 보존하고 서버별 새 작업 브랜치를 생성했다. SigNoZ·ingester 정지 후 SQLite를 복사하고 원본/복사본 일치 및 백업 `quick_check=ok`를 확인했다. migrator 종료 코드 양쪽 `0`, ClickHouse 트레이스 마이그레이션 `1017`의 `finished` 기록을 확인한 뒤 서비스를 기동했다.
- root 전용 보관 경로: 203 `/app/signoz-runtime/upgrade-v0.143.0-RdHhIv`, 204 `/app/signoz-runtime/upgrade-v0.143.0-ytUPCW`. 변경 전 Foundry·바이너리·Git patch·유효 Compose·컨테이너 상태·SQLite·ClickHouse 스키마·sayis 권한과 204 override가 포함된다. ClickHouse 전체 데이터 백업은 아니다.
- 정지 요청 → API health 확인(KST): 203 `09:08:08 → 09:08:50`, 204 `09:09:31 → 09:10:08`. Collector ready는 각각 `09:08:50`, `09:10:13`이다. 실제 수집 누락량을 측정한 값은 아니다.
- 양쪽 SigNoZ `v0.143.0` / API health `ok` / Docker `healthy`, Collector `Server available`, 재시작 횟수 `0`, SQLite `quick_check=ok`, sayis-dashboard-api `healthy`를 확인했다. 별도 성능 시험은 수행하지 않았다.
- 기존 테이블 135개와 engine/sorting/partition/primary key를 유지했다. 트레이스 로컬·분산 테이블에 AI 관련 컬럼 각각 26개와 로컬 테이블 인덱스 3개가 반영됐다. 복제 대기열·대기열 오류·미완료 mutation은 모두 `0`이다. ClickHouse·ZooKeeper 컨테이너 ID/시작 시각, 모든 기존 mount, sayis 권한, 204 override가 유지됐다.
- SQLite 기존 ID 목록 보존: 203 dashboard 14 / rule 1 / notification_channel 4 / quick_filter 5, 204 각각 1 / 0 / 0 / 5개를 확인했다.
- `09:10:25`(KST) 최근 2분 실적재: 203 CPU 17,464 / 메모리 8,096 / 네트워크 8,828 / 트레이스 964건, 204 각각 192 / 114 / 112 / 25건. 메트릭 이름은 `system.cpu.time`, `system.memory.usage`, `system.network.io`이며 재시작 전후가 함께 포함된 구간이다.
- 기동 중 기존 active-query 디렉토리·license 조회 오류 및 OpAMP 연결 재시도가 있었으나 ready 이후 최종 조회 시 SigNoZ·Collector ERROR는 양쪽 `0`이었다. 관련 설정을 임의 변경하지 않았다. 인증은 새 공식 기본 opaque provider를 적용했으며 기존 사용자는 한 번 다시 로그인한다.
- 오프라인 설치기 점검 사항은 사용자 지시로 담당 작업에 정보만 전달한 상태다. 이번 작업은 Docker 203·204 배포이며 오프라인 번들이나 K3s 변경은 포함하지 않았다.

## 2026-09-18 203·204 Docker 업그레이드

- SigNoZ `v0.142.0` → `v0.142.1`만 적용했다. 유효 Compose 비교에서 SigNoZ 이미지 외 변경은 없었다. Collector/migrator 버전은 유지하며 migrator는 재실행하지 않았다.
- SigNoZ·ingester 정지 후 SQLite를 보관하고 `quick_check=ok`를 확인했다. SigNoZ를 재생성하고 기존 ingester를 재개했다.
- 보관 경로: 203 `/app/signoz-runtime/upgrade-v0.142.1-P1kz1e`, 204 `/app/signoz-runtime/upgrade-v0.142.1-rkRJr8`. 기존 Foundry 파일·유효 Compose·Git patch·컨테이너 상태·SQLite와 204 override를 보관했다. ClickHouse 전체 데이터 백업은 아니다.
- 양쪽 버전 API `v0.142.1`, health `ok`, SigNoZ·Collector 재시작 횟수 `0`을 확인했다. 별도 시험 환경이나 성능 시험은 실행하지 않았다.
- 최초 패치 적용은 문맥 없는 diff 옵션 누락으로 실패했다. 서비스 정지 전이었으며, 옵션을 바로잡아 같은 보관본·작업 브랜치에서 배포를 완료했다.

## 2026-09-17 203·204 Docker 업그레이드

- SigNoZ `v0.141.1` → `v0.142.0`, Collector / migrator `v0.144.9` → `v0.144.10`을 적용했다. 공식 Foundry `v0.2.17`로 산출물을 재생성했다.
- 유효 Compose 비교에서 위 세 서비스 이미지 외의 변경은 없었다. 나머지 생성 설정은 변경 전과 바이트 단위로 동일하다.
- 기존 미커밋 변경과 Foundry 파일을 보존하고, SigNoZ·ingester 정지 후 SQLite를 복사했다. 정지 상태 원본과 복사본 일치 및 백업 `quick_check=ok`를 확인했다. ClickHouse 전체 데이터 백업은 아니다.
- 공식 migrator의 종료 코드가 양쪽 모두 `0`인 것을 확인한 뒤 SigNoZ·ingester를 기동했다. 양쪽 버전 API는 `v0.142.0`, health는 `ok`이며 기동 직후 restart count는 `0`이다.
- 보관 경로: 203 `/app/signoz-runtime/upgrade-v0.142.0-71YMwp`, 204 `/app/signoz-runtime/upgrade-v0.142.0-yzBovy` (root 전용).
- 정지 요청 → API health 확인(KST): 203 `17:39:00 → 17:39:28`, 204 `17:40:07 → 17:40:33`. 실제 수집 누락량을 측정한 값은 아니다.
- 최종 확인: 양쪽 SigNoZ `healthy`, Collector `Server available`, SQLite `quick_check=ok`, 복제 대기열·대기열 오류·미완료 mutation `0`. 조회 직전 30초의 SigNoZ·Collector ERROR 로그는 `0`건이다. sayis-dashboard-api 컨테이너도 양쪽 `healthy`이며 성능 측정은 하지 않았다.
- ClickHouse·ZooKeeper의 컨테이너 ID/시작 시각, 모든 기존 데이터 mount, `sayis` 권한, 204 override는 유지됐다. 트레이스 로컬/분산 테이블에 새 `attributes_promoted` JSON 컬럼이 적용됐다.
- 최근 2분 실적재 조회(KST): 203 `17:40:07` CPU 17,576 / 메모리 8,198 / 네트워크 8,888 / 트레이스 679건, 204 `17:41:07` 각각 280 / 162 / 180 / 24건. 메트릭 이름은 기존 검증과 동일하며 조회 구간에 재시작 전후가 함께 포함된다.
- 별도 성능·호환성 시험은 사용자 지시에 따라 중단했으며, 시험 통과 또는 성능 개선을 주장하지 않는다.

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
- `telemetrykeeper.kind`는 `clickhousekeeper`를 사용한다. 기존 ZooKeeper 메타데이터는 공식 converter로 변환했으며, 예전 ZooKeeper 데이터 디렉토리를 Keeper에 직접 연결하지 않는다.
- ClickHouse macro는 기존 값과 일치해야 한다.
  - `shard: "01"`
  - `replica: "example01-01-1"`
- ClickHouse의 `sayis` 사용자는 기존 승인대로 `default`와 동일한 권한으로 유지한다. SELECT 전용으로 축소하지 않는다.
  - 인증 설정: `password`
  - 기존 활성 설정의 네 권한 플래그를 casting에도 유지한다.
  - 양쪽 `SHOW GRANTS`를 계정명만 정규화해 비교하고, 업그레이드 전후 `sayis` 권한도 비교한다.
  - 원본 암호는 프라이빗 저장소의 casting에 유지한다.
- 영구 데이터는 호스트 bind mount를 사용한다.
  - `/data/sayit-clickhouse:/var/lib/clickhouse`
  - `/data/sayit-sqlite:/var/lib/signoz`
  - `/data/sayit-clickhouse-keeper:/var/lib/clickhouse-keeper`
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
  - `/data/sayit-clickhouse-keeper:/var/lib/clickhouse-keeper`
- ingester 포트는 아래 포트를 노출해야 한다.
  - `4317:4317`
  - `4318:4318`
  - `8889:8889`
- ingester volume에는 아래 secret mount가 있어야 한다.
  - `/app/secrets/uptime_kuma_api_key:/app/secrets/uptime_kuma_api_key:ro`
- compose network name은 Foundry 공식 이름인 `signoz-network`여야 한다.
- 서비스 간 통신은 Foundry 공식 서비스명과 공식 alias를 사용한다.

### `deploy/foundry/pours/deployment/ingester/ingester.yaml`

- SigNoZ `v0.143.0`부터 공식 AI 프로세서 `signozspanmapper`, `signozllmpricing`의 정의와 traces pipeline 항목을 포함한다. 순서는 `signozspanmetrics/delta → signozspanmapper → signozllmpricing → batch`다. OpAMP는 설정 내용을 관리하지만 pipeline 목록에 자동 추가하지 않는다.
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

### v0.143.0 필수 변경

- 공식 안내: https://signoz.io/docs/operate/migration/upgrade-0-143/
- Foundry `v0.3.0`으로 위 프로세서를 포함한 설정을 생성한다. 기존 custom traces processors 목록이 기본 목록을 대체하므로 casting 자체에 두 프로세서를 반영한다.
- Collector `v0.144.12`의 ClickHouse 트레이스 마이그레이션 `1017`은 AI 속성 13개와 존재 여부 컬럼·인덱스를 추가한다. 기존 공식 migrator 명령으로 처리하며 별도 수동 DDL을 추가하지 않는다.
- 인증은 공식 기본 opaque provider를 따른다. 기존 JWT secret만으로 JWT provider가 선택되지 않으며, 업그레이드 후 사용자는 한 번 다시 로그인한다. JWT provider를 별도로 강제하지 않는다.

## 업그레이드 조회와 승인 후 준비

### 조회 단계 — 배포하지 않음

`gomdobi/signoz`의 `origin/main:deploy/foundry/casting.yaml` 버전과 upstream 최신 정식 릴리즈를 먼저 비교한다. RC·개발 브랜치는 대상에서 제외한다. 업그레이드 대상이면 공식 릴리즈 노트에서 Collector·migrator·ClickHouse·ClickHouse Keeper·Foundry 변경을 우선 확인한다. 단순 조회 지시를 서버 접속, 파일 재생성, 배포나 `main` 병합 승인으로 확대하지 않는다.

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
grep -nE 'signoz/signoz:v|signoz-otel-collector:v|clickhouse/clickhouse-server:|clickhouse/clickhouse-keeper:|9000:9000|8123:8123|9181:9181|8889:8889|uptime_kuma_api_key|/data/sayit-clickhouse:/var/lib/clickhouse|/data/sayit-clickhouse-keeper:/var/lib/clickhouse-keeper' deploy/foundry/pours/deployment/compose.yaml
grep -nE 'job_name: uptime-kuma|password_file: /app/secrets/uptime_kuma_api_key|endpoint: 0.0.0.0:8889|prometheus' deploy/foundry/pours/deployment/ingester/ingester.yaml
grep -nE 'replica: example01-01-1|shard: "01"|sayis:|access_management:|named_collection_control:|show_named_collection' deploy/foundry/pours/deployment/telemetrystore/clickhouse/config-0-0.yaml
test "$(grep -Fc '/data/sayit-clickhouse:/var/lib/clickhouse' deploy/foundry/pours/deployment/compose.yaml)" -eq 1
! grep -qE 'signoz-clickhouse|signoz-telemetrystore-0-0-data:/var/lib/clickhouse' deploy/foundry/pours/deployment/compose.yaml
```

3. `sayis-dashboard-api`에 영향을 줄 수 있는 ClickHouse 구조 변경을 확인한다.

- ClickHouse, collector, telemetrystore migrator 이미지 버전을 이전 배포와 비교한다.
- telemetry 테이블의 engine, sorting key, partition key, primary key를 비교한다.
- View와 Materialized View의 생성 SQL을 비교한다.
- 구조 변경이 있으면 영향 내용을 먼저 보고한다. API 실행 계획·응답시간 비교 등 별도 성능 시험은 사용자가 요청한 경우에만 수행한다.

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
test "$(findmnt -n -o TARGET -T /data/sayit-clickhouse-keeper)" = "/data"
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
test "$(findmnt -n -o TARGET -T /data/sayit-clickhouse-keeper)" = "/data"
sudo docker compose \
  -f deploy/foundry/pours/deployment/compose.yaml \
  pull
sudo docker compose \
  -f deploy/foundry/pours/deployment/compose.yaml \
  up -d
```

## 100.204 외부망 풀스택 배포

100.204의 호스트 전용 설정은 Git 저장소 밖의 `/app/signoz-runtime/docker-compose.204.override.yaml`에서 유지한다. 2026-09-28 Keeper 전환 시 `signoz-telemetrykeeper-zookeeper-0` 키만 `signoz-telemetrykeeper-clickhousekeeper-0`으로 변경했으며 나머지 값은 그대로 보존했다.

```bash
cd /app/signoz
test "$(findmnt -n -o TARGET -T /data/sayit-clickhouse)" = "/data"
test "$(findmnt -n -o TARGET -T /data/sayit-sqlite)" = "/data"
test "$(findmnt -n -o TARGET -T /data/sayit-clickhouse-keeper)" = "/data"
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
findmnt -n -o SOURCE,FSTYPE,TARGET -T /data/sayit-clickhouse-keeper
sudo docker inspect signoz-telemetrystore-clickhouse-0-0 \
  --format '{{range .Mounts}}{{if eq .Destination "/var/lib/clickhouse"}}{{.Type}} {{.Source}} {{.Destination}}{{end}}{{end}}'
sudo docker inspect signoz-signoz-0 \
  --format '{{range .Mounts}}{{if eq .Destination "/var/lib/signoz"}}{{.Type}} {{.Source}} {{.Destination}}{{end}}{{end}}'
sudo docker inspect signoz-telemetrykeeper-clickhousekeeper-0 \
  --format '{{range .Mounts}}{{if eq .Destination "/var/lib/clickhouse-keeper"}}{{.Type}} {{.Source}} {{.Destination}}{{end}}{{end}}'
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
- ClickHouse와 ClickHouse Keeper는 healthy 상태여야 한다.
- ClickHouse 데이터 mount는 `bind /data/sayit-clickhouse /var/lib/clickhouse`여야 한다.
- SQLite 데이터 mount는 `bind /data/sayit-sqlite /var/lib/signoz`여야 한다.
- Keeper 데이터 mount는 `bind /data/sayit-clickhouse-keeper /var/lib/clickhouse-keeper`여야 한다. 이전 ZooKeeper 컨테이너는 정지 상태로 보존하며 재기동하지 않는다.
- 세 데이터 경로는 `/dev/mapper/vg_data-lv_data`의 ext4 `/data` 아래에 있어야 한다.
- migrator는 `exited 0`이어야 한다.
- 완료되지 않은 ClickHouse mutation 수는 `0`이어야 한다.
- 복제 대기열 건수만으로 장애를 단정하지 않는다. 정상 `MERGE_PARTS`와 같은 일시적 작업과 반복 실패를 구분하고, 예외·재시도 증가·지연을 함께 확인한다. 재발 진단은 저장소 운영 런북을 따른다.
- 최신 metrics write 시각이 현재 시각으로 계속 갱신되어야 한다. 로그 유입 `0`건을 Infrastructure 메트릭 유입 없음으로 표현하지 않는다.
- Collector는 Docker healthcheck가 없을 수 있다. 컨테이너 `running`만으로 완료 판정하지 않고 health endpoint, 전송 실패·수신 거부 지표와 실제 신규 적재를 확인한다.
- 필수 포트와 Uptime Kuma/Prometheus collector 설정이 유지되어야 한다.
- `sayis` 계정은 기존 승인된 `default` 동등 권한을 유지해야 한다. `SHOW GRANTS FOR sayis`와 `SHOW GRANTS FOR default`를 계정명만 정규화해 비교하고, 변경 전후 권한이 같은지도 확인한다.
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
