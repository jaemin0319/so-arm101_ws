# shellcheck shell=bash
# scripts/*.sh 가 맨 앞에서 source 하는 공통 함수. 직접 실행하지 않는다.
set -euo pipefail

_SO101_SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# activate.sh 는 set -u 에서 conda 훅이 미정의 변수를 참조할 수 있어 잠시 끈다.
set +u
SO101_QUIET=1 . "$_SO101_SCRIPTS/activate.sh"
set -u

# 1 이면 명령을 실행하지 않고 출력만 한다(--dry-run).
SO101_DRY_RUN="${SO101_DRY_RUN:-0}"
# 1 이면 장치를 열지 않고 lerobot 이 인자를 어떻게 해석하는지만 출력한다(--check).
SO101_CHECK="${SO101_CHECK:-0}"
for _a in "$@"; do
    case "$_a" in
        --dry-run) SO101_DRY_RUN=1 ;;
        --check) SO101_CHECK=1; SO101_DRY_RUN=1 ;;
        --) break ;;
    esac
done
unset _a

# 스크립트 맨 앞 주석 블록을 도움말로 출력
so101_usage() { awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"; }

so101_log()  { printf '\033[1;36m[SO-ARM]\033[0m %s\n' "$*" >&2; }
so101_warn() { printf '\033[1;33m[경고]\033[0m %s\n' "$*" >&2; }
so101_die()  { printf '\033[1;31m[오류]\033[0m %s\n' "$*" >&2; exit 1; }

# 명령을 보기 좋게 출력한 뒤 실행(또는 dry-run 이면 출력만).
so101_run() {
    printf '\033[1;32m$\033[0m' >&2
    printf ' %q' "$@" >&2
    printf '\n' >&2
    if [ "$SO101_CHECK" = "1" ]; then
        case "$1" in lerobot-*) python "$_SO101_SCRIPTS/_check_cli.py" "$@"; return ;; esac
    fi
    if [ "$SO101_DRY_RUN" = "1" ]; then return 0; fi
    "$@"
}

# 회전 값(0/90/180/-90) 확인
_so101_rot() {
    case "$1" in 0|90|180|-90) echo "$1" ;; 270) echo "-90" ;; *) so101_die "회전 값은 0, 90, 180, -90 중 하나: '$1'" ;; esac
}

# lerobot --robot.cameras 에 넣을 문자열. 인자: 쓸 카메라 이름들(기본 front wrist)
so101_cameras() {
    local names=("$@")
    [ ${#names[@]} -eq 0 ] && names=(front wrist)
    local parts=() n path rot
    for n in "${names[@]}"; do
        case "$n" in
            front) path="$SO101_CAM_FRONT"; rot="$(_so101_rot "$SO101_CAM_FRONT_ROTATION")" ;;
            wrist) path="$SO101_CAM_WRIST"; rot="$(_so101_rot "$SO101_CAM_WRIST_ROTATION")" ;;
            *) so101_die "알 수 없는 카메라 이름: $n (front/wrist)" ;;
        esac
        parts+=("$n: {type: opencv, index_or_path: $path, width: $SO101_CAM_WIDTH, height: $SO101_CAM_HEIGHT, fps: $SO101_CAM_FPS, fourcc: $SO101_CAM_FOURCC, rotation: $rot}")
    done
    local IFS=','
    echo "{${parts[*]}}"
}

# 장치 경로가 있는지 확인(없으면 경고만; dry-run 은 통과)
so101_check_path() {
    local path="$1" what="$2"
    if [ ! -e "$path" ]; then
        if [ "$SO101_DRY_RUN" = "1" ]; then so101_warn "$what 경로 없음: $path"; return 0; fi
        so101_die "$what 경로가 없다: $path
  - 연결/전원을 확인하고 'bash scripts/check_devices.sh' 로 현재 장치 목록을 본다.
  - 경로가 바뀌었으면 config/so101.env 를 고친다."
    fi
}

so101_check_cameras() {
    local n
    for n in "$@"; do
        case "$n" in
            front) so101_check_path "$SO101_CAM_FRONT" "front 카메라" ;;
            wrist) so101_check_path "$SO101_CAM_WRIST" "wrist 카메라" ;;
        esac
    done
}

# Hugging Face 로그인 사용자 이름(없으면 빈 문자열)
so101_hf_whoami() {
    python - <<'PY' 2>/dev/null || true
from huggingface_hub import HfApi
try:
    print(HfApi().whoami()["name"])
except Exception:
    pass
PY
}

# repo_id 에 '/' 가 없으면 HF_USER/ 를 앞에 붙인다.
so101_repo_id() {
    case "$1" in */*) echo "$1" ;; *) echo "$HF_USER/$1" ;; esac
}
