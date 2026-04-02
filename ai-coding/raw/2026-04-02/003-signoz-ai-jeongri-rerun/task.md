# Task 003: signoz AI정리 재실행 원천 데이터 보완

## 사용자 요청

- `다 포함하고`
- `AI정리`

## 작업 목표

- 현재 미추적 항목을 전부 포함한다.
- 부분 생성 상태였던 `ai-coding/raw/2026-04-02/003-signoz-ai-jeongri-rerun/` 작업 단위를 보완한다.
- 현재 스레드와 현재 저장소 상태 근거만 기록한다.

## 실제 변경 내용

- 생성 파일:
  - `ai-coding/raw/2026-04-02/003-signoz-ai-jeongri-rerun/task.md`
  - `ai-coding/raw/2026-04-02/003-signoz-ai-jeongri-rerun/meta.json`
- 기존 파일 유지:
  - `ai-coding/raw/2026-04-02/003-signoz-ai-jeongri-rerun/diff.patch`
- 현재 포함 대상(untracked) 확인:
  - `AGENTS.md`
  - `ai-coding/raw/2026-04-02/002-signoz-aijeongri-current-thread/`
  - `ai-coding/raw/2026-04-02/003-signoz-ai-jeongri-rerun/`
  - `ai-coding/raw/2026-04-02/003-signoz-thread-ai-raw-global-agents/`

## 실행 명령

```bash
cd /Users/gomdobi/PROJECT/REPOSITORY/signoz
git status --short
find ai-coding/raw/2026-04-02 -maxdepth 2 -type d | sort
find ai-coding/raw/2026-04-02/003-signoz-ai-jeongri-rerun -maxdepth 1 -type f | sort
```

## 검증 명령

```bash
python3 - <<'PY'
import json
json.load(open('ai-coding/raw/2026-04-02/003-signoz-ai-jeongri-rerun/meta.json', encoding='utf-8'))
print('OK')
PY
find ai-coding/raw/2026-04-02/003-signoz-ai-jeongri-rerun -maxdepth 1 -type f | sort
```

## 검증 결과

- `003-signoz-ai-jeongri-rerun` 경로가 `task.md`, `diff.patch`, `meta.json` 3종으로 보완됨
- 포함 대상 미추적 항목 목록 확인 완료
- JSON 파싱 정상

## 버그 및 제약 사항

- 확인된 source 버그: unknown
- `AGENTS.md` 생성 주체: unknown

## 다음 작업 맥락

- 사용자 지시대로 현재 포함 대상 전체를 단일 커밋으로 반영한다.
- 병합/가공/train/eval 생성은 `/Users/gomdobi/PROJECT/REPOSITORY/ai-devops-dataset`에서만 수행한다.
