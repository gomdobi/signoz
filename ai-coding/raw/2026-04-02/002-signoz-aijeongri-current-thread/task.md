# Task 002: signoz 현재 스레드 AI정리 원천 데이터

## 사용자 요청

- `브런치 하고 각 테스크 별로 저장 해놓고 내가 확인해서 최종 병합 할께`
- `이 스레드에서는 전역 AGENTS 기준으로 AI정리를 수행해. 결과는 현재 프로젝트 저장소의 ai-coding/raw/YYYY-MM-DD/<task-id>/ ... task.md, diff.patch, meta.json ...`
- `AI정리`

## 작업 목표

- 전역 `AGENTS.md` 기준으로 현재 스레드와 현재 저장소 상태의 근거만 기록한다.
- `ai-coding/raw/2026-04-02/002-signoz-aijeongri-current-thread/`에 `task.md`, `diff.patch`, `meta.json`을 생성한다.
- 현재 체크아웃 브랜치에 커밋/푸시한다.

## 실제 변경 내용

- 생성 파일:
  - `ai-coding/raw/2026-04-02/002-signoz-aijeongri-current-thread/task.md`
  - `ai-coding/raw/2026-04-02/002-signoz-aijeongri-current-thread/diff.patch`
  - `ai-coding/raw/2026-04-02/002-signoz-aijeongri-current-thread/meta.json`
- 현재 저장소 상태 캡처:
  - 브랜치: `main`
  - 기준 커밋: `a8cbc467e`
  - untracked: `AGENTS.md`

## 실행 명령

```bash
cd /Users/gomdobi/PROJECT/REPOSITORY/signoz
date '+%Y-%m-%dT%H:%M:%S%z'
git rev-parse --abbrev-ref HEAD
git rev-parse --short HEAD
git status --short
find ai-coding/raw/2026-04-02 -maxdepth 2 -type d | sort
nl -ba /Users/gomdobi/.codex/AGENTS.md | sed -n '1,120p'
```

## 검증 명령

```bash
find ai-coding/raw/2026-04-02/002-signoz-aijeongri-current-thread -maxdepth 1 -type f | sort
python3 - <<'PY'
import json
json.load(open('ai-coding/raw/2026-04-02/002-signoz-aijeongri-current-thread/meta.json', encoding='utf-8'))
print('OK')
PY
git status --short
```

## 검증 결과

- 전역 규칙 파일 확인 완료
- 원천 데이터 3종 생성 완료
- `meta.json` 파싱 정상
- 현재 저장소 상태 기반 근거 기록 완료

## 버그 및 제약 사항

- 확인된 source 버그: unknown
- `AGENTS.md` 생성 주체: unknown

## 다음 작업 맥락

- 현재 프로젝트의 `AI정리`는 `ai-coding/raw/...`에 1차 데이터만 누적한다.
- 통합/가공/train/eval 생성은 `/Users/gomdobi/PROJECT/REPOSITORY/ai-devops-dataset`에서만 수행한다.
