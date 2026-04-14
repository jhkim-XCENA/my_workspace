Register a new GitHub issue to any xcena-dev repository.

`$ARGUMENTS` format: `<repo> <description>`
- `<repo>`: short repo name under xcena-dev (e.g., `sdk_release`, `pxcc`, `mu_lib`, `pxl`)
- `<description>`: free-form description of the problem or feature request

Examples:
- `/gh-issue sdk_release SIGBUS when running data_copy via Claude Code due to THP`
- `/gh-issue pxl memAlloc returns null when device has fragmented free memory`

## Steps

### 1. Parse arguments
```
REPO=$(echo "$ARGUMENTS" | awk '{print $1}')
DESC=$(echo "$ARGUMENTS" | cut -d' ' -f2-)
FULL_REPO="xcena-dev/$REPO"
```
Validate: run `gh repo view $FULL_REPO` to confirm it exists. If not, stop with an error.

### 2. Read current context
```bash
# Get HEAD of current working repo (if inside one)
COMMIT=$(git rev-parse --short=7 HEAD 2>/dev/null || echo "N/A")
```

### 3. Analyze the description

From `$DESC` and your knowledge of the codebase, determine:
- **Title**: concise one-line summary (≤72 chars)
- **문제 (Problem)**: what breaks and how to reproduce
- **영향 범위 (Scope)**: which files/modules/APIs are affected — read relevant source if needed
- **구현 방향 (Approach)**: suggested implementation direction
- **테스트 (Tests)**: what to verify after the fix
- **Label(s)**: choose from `bug`, `feature`, `test`, `infra`, `documentation`, `priority:high`, `priority:medium`

### 4. Present draft to user

Show the draft issue before filing:
```
Title: <title>
Repo:  xcena-dev/<repo>
Labels: <labels>

Body:
## 이슈 리포트 당시의 커밋
<commit>

## 문제
<problem>

## 영향 범위
<scope>

## 구현 방향
<approach>

## 테스트
<tests>
```

Ask the user to confirm or suggest changes before filing.

### 5. File the issue
```bash
gh issue create --repo xcena-dev/$REPO \
  --title "<title>" \
  --label "<label>" \
  --body "$(cat <<'EOF'
## 이슈 리포트 당시의 커밋
<commit>

## 문제
<problem>

## 영향 범위
<scope>

## 구현 방향
<approach>

## 테스트
<tests>
EOF
)"
```

### 6. Report
Show the created issue URL and number.
