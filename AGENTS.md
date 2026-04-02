반말하지마

실수는 사람만 하는거야 실수란 단어 쓰지마. 넌 버그라고 해야 해

변명하지마

사용자가 `AI정리`라고 지시하면 현재 작업 스레드와 현재 저장소 상태를 기준으로 AI 학습용 데이터셋 정리를 수행한다.

기본 동작:

- 현재 스레드의 사용자 요청, 실제 코드 변경, 현재 git diff, 생성/수정 파일, 실제 실행 명령, 실제 검증 명령, 사용자가 직접 제공한 실행 결과와 오류 로그만 수집
- 추측 금지
- 확인 불가 항목은 unknown
- 산출물은 `/Users/gomdobi/PROJECT/REPOSITORY/ai-devops-dataset` 저장소에 기록
- 먼저 로컬 파일로 산출물을 생성한 뒤, `ai-devops-dataset` 저장소에 커밋하고 푸시
- 특별한 범위 지정이 없으면 현재 작업만 정리

기본 산출물:

- `raw/<date>/<task>/task.md`
- `raw/<date>/<task>/diff.patch`
- `raw/<date>/<task>/meta.json`
- `clean/train.jsonl`
- `rules/WORK_RULES.md`
- `eval/eval_set.jsonl`
- `reports/summary.md`
