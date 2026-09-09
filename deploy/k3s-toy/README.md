# SigNoZ 공식 Kustomize 토이프로젝트

2026-09-09 착수. **토이프로젝트가 완성될 때까지 기존 Docker/Compose 업그레이드 방식은 그대로 유지한다.**

이 디렉터리는 공식 Foundry/Kustomize 생성·로컬 검증 전용 실험 경로다. 기존 `deploy/foundry`, 출하용 Docker 번들 제작·설치기, 203·204 배포, 기존 업그레이드 문서를 대체하거나 변경하지 않는다. 기존 업그레이드 작업은 이 토이프로젝트의 결과를 기다리도록 바꾸지 않는다. 자동 배포·새 CI 연결·main 병합은 포함하지 않는다.

## 기준

- [SigNoZ 공식 Kustomize 설치 안내](https://signoz.io/docs/setup/kubernetes/kustomize/)
- [Foundry v0.2.17 공식 casting 예제](https://github.com/SigNoz/foundry/blob/v0.2.17/docs/examples/kubernetes/kustomize/casting.yaml)
- [공식 casting 설정](https://github.com/SigNoz/foundry/blob/v0.2.17/docs/concepts/casting.md)

SigNoZ의 공식 구조·설정·기동·마이그레이션 방식을 최대한 따른다. SigNoZ에 자체 NetworkPolicy, Pod 보안 정책, RBAC 축소, 별도 제어기를 임의로 추가하지 않는다. 필요한 환경 차이와 실제 보안 문제는 공식 권장과 구분하여 보고한다. 공식 방식에서 벗어나는 변경은 근거·영향을 확인하고 별도 승인 대상으로 다룬다. SigNoZ 외 제품의 추가 강화는 분리하며, K3s 공통 정책도 SigNoZ에 미치는 영향을 먼저 확인한다.

## 현재 입력과 공식 기본 구성

[casting.yaml](casting.yaml)은 공식 최소 예제에서 **기존 검증 릴리스의 이미지·버전 세 쌍만** 명시한다. 데이터 저장소 종류·네트워크·권한·스토리지 크기 등은 새 정책으로 덮어쓰지 않았다.

| 항목 | 이 실험의 기준 |
|---|---|
| Foundry | 기존 로컬 공식 바이너리 `v0.2.17`, commit `273dec4` |
| SigNoZ | `v0.140.0` |
| Collector 및 migrator | `v0.144.9` |
| ClickHouse | `25.12.5` |
| Keeper | Foundry 기본 `clickhouse/clickhouse-keeper:25.12.5` |
| Metastore | Foundry 기본 `postgres:16` |
| Operator 및 exporter | Foundry 기본 `0.25.3` |
| Histogram initContainer | Foundry 기본 `alpine:3.18.2` |
| Namespace·이름 접두어 | 공식 예제의 `signoz`; 실제 27번 기존 `sayit`의 대체/이전 결정은 아님 |

`make check`는 SigNoZ·Collector·ClickHouse 이미지/버전을 기존 `../foundry/casting.yaml`과 읽기 전용으로 비교한다. 버전 차이가 나면 이 실험 검사가 실패할 뿐, 기존 업그레이드나 기존 소스를 수정하지 않는다. 추가 구성요소의 mutable tag와 digest·오프라인 반입 확정은 후속 배포 준비 사항이다.

기본 PostgreSQL/Keeper 생성은 **기존 SQLite/ZooKeeper를 삭제·초기화·이전했다는 뜻이 아니다.** 현재 27번 DB/PVC와 사용자·대시보드·연계 데이터는 이 단계에서 건드리지 않는다.

## 로컬 실행

필요 도구: Foundry `v0.2.17`, `kubectl`의 Kustomize, `make`, Ruby의 기본 `yaml/json/open3/minitest`. 이번 확인 환경은 kubectl `v1.37.0` / Kustomize `v5.8.1` / Ruby `2.6`다. Ruby는 로컬 검사에만 사용하며 K3s 서버에 설치하지 않는다.

저장소 루트에서:

```bash
make -C deploy/k3s-toy check
make -C deploy/k3s-toy test
```

실제 생성 명령은 이 디렉터리 안에서 실행되는 공식 `foundryctl forge -f casting.yaml -p ./pours`다. 익명 사용 통계와 업데이트 알림만 CLI 옵션으로 끈다. `kubectl kustomize`는 로컬 렌더링에만 사용한다. 이 Makefile에는 `cast`, `apply`, SSH, 설치·삭제 대상이 없다.

생성된 `pours/`와 `casting.yaml.lock`은 Git에서 제외했다. 공식 예제의 접속 설정이 포함될 수 있으므로 전체 생성물을 로그·협업 메시지로 출력하지 않는다. 실제 사이트 암호를 이 casting이나 생성물에 추가하지 않는다. 검사는 이미지·객체 수·마이그레이션 단계·렌더링 SHA-256만 출력한다.

`validate.rb`는 공식 Kubernetes 객체 구조, 버전 대응, migrator/Collector 일치, 마이그레이션 순서, 환경변수 타입, 중복 객체/환경변수, 의도하지 않은 MCP 및 추가 정책 유입을 확인한다. **API 서버 스키마 검증, Operator 실행, 실제 적재·조회, 업그레이드·복원 검증을 대신하지 않는다.**

## 1차 검증 결과

- `foundryctl forge`: 종료 코드 0, YAML 파일 32개 생성.
- `kubectl kustomize`: 종료 코드 0, 실제 적용 집합 29개. MCP 파일은 생성되지만 적용 집합에는 포함되지 않는다.
- 활성 이미지 8종, SigNoZ/Collector/ClickHouse 버전 일치.
- 공식 migration Job: `ready → bootstrap → sync up → async up`; 네 단계 모두 대상 Collector 이미지 사용. 초기 구성의 순서를 검사한 것이며 기존 DB에 무조건 재실행하라는 지시가 아니다.
- 검사 테스트 6개, assertion 7개 통과. 이미지 불일치·환경변수 타입 오류·추가 정책·임의 Ruby YAML 객체·YAML alias 거부 확인.
- 기존 `deploy/foundry` 및 `deploy/README.md`는 착수 기준 `eecd3aa2608c1ee76e8c9c80447f1e6d9a091900`과 diff 없음.
- 27번 배포, 203·204 접속·변경, DB 마이그레이션, main 병합은 이번 단계에서 실행하지 않았다.

## 공식 버전별 차이와 후속 확인

1. **문서의 main과 설치한 릴리스를 구분한다.** 현재 Foundry main의 SigNoZ StatefulSet 템플릿에는 SQLite/PVC 분기가 있지만, 고정한 `v0.2.17` 템플릿에는 없다. main 소스의 기능을 현재 바이너리 지원으로 단정하지 않는다. 이번 실험은 해당 릴리스의 공식 기본 PostgreSQL/Keeper 구성이다. [v0.2.17 템플릿](https://github.com/SigNoz/foundry/blob/v0.2.17/internal/casting/kuberneteskustomizecasting/templates/signoz/statefulset.yaml.gotmpl)
2. `v0.2.17` 생성 CHI의 `replicasCount`는 0이며 Operator `0.25.3` 소스는 0을 1로 정규화한다. 이 값을 실행 실패로 단정하거나 자체 패치로 바꾸지 않았다. 실제 Operator reconcile 확인은 후속 단계다. [공식 정규화 코드](https://github.com/Altinity/clickhouse-operator/blob/0.25.3/pkg/model/chi/normalizer/normalizer.go#L840-L844)
3. 공식 `cast`는 CRD 4개를 GitHub에서 적용한 뒤 Kustomize를 적용한다. Histogram initContainer도 기동 중 공식 바이너리를 다운로드한다. 오프라인 실험에서는 공식 자산의 반입과 경로 연결이 필요하지만 아직 임의 대체하지 않았다. [공식 배포 구현](https://github.com/SigNoz/foundry/blob/v0.2.17/internal/casting/kuberneteskustomizecasting/casting.go)
4. 공식 기본 Metastore 자격정보와 ClickHouse 사용자 구성을 실제 사이트 계정에 그대로 덮어쓰지 않는다. 기존 연계에 필요한 사용자/Secret 연결과 데이터 전환 범위를 먼저 확정한다. 이 항목은 추가적인 SigNoZ 보안 재설계가 아니라 현재 연결·데이터 영향 확인이다.

## 협업 분담과 다음 단계

- **SigNoZ 업그레이드 작업:** 이 저장소의 별도 토이 경로에서 공식 생성·버전·마이그레이션 검증을 담당한다.
- **`k3s 구성` 작업** (`01a069e6-b44f-7d80-85bb-e63ac7cb6c6f`): `sayit.install`의 토이 전용 경로에서 기존 Service/DNS·포트·Secret 키·PVC 및 다른 제품 연계 대응표와 연결안을 담당한다.
- 공식 casting/생성물과 기존 `sayis-config`가 같은 SigNoZ 리소스를 서로 덮어쓰지 않도록 적용 책임을 정한다. 자체 설정 도구 유지 자체를 필수 조건으로 삼지 않는다.
- 27번 전환 전에 기존 데이터를 보존·이전할 범위, 새 공식 구성과 현재 구성의 교체 범위, 필요한 연계 변경을 확인한다. 토이라는 이유로 PVC 삭제나 계정 초기화를 추정하지 않는다.
- 토이 완료 판정은 공식 방식 신규 설치·수집·조회, 한 차례 버전 업그레이드, 설정 재적용, 재기동, 데이터 복원 및 기존 연계 검증을 근거로 사용자와 확정한다. 완료 전뿐 아니라 **기존 운영 방식 교체 자체도 별도 지시 없이 실행하지 않는다.**

이번 협업 요청은 전달했으며, 상대 작업의 구현 결과·커밋은 아직 수신되지 않았다. 자체 검증 완료와 상대 작업 완료를 구분한다.
