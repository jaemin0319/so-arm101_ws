#!/usr/bin/env bash
# SO-ARM_ws 설치 (Ubuntu 24.04 x86_64). 여러 번 실행해도 안전하다. 보통 5~10분(인터넷 속도에 따라).
#
#   bash scripts/install.sh                # 기본
#   bash scripts/install.sh --demo         # + 예제 데이터셋(454MB)·모델(198MB) 받기
#   bash scripts/install.sh --dialout      # + 시리얼 포트 권한(sudo usermod -aG dialout). 이후 재로그인 필요
#   bash scripts/install.sh --torch cu128  # torch 빌드 강제(auto | cu13 | cu128)
#   bash scripts/install.sh --env-name X   # conda 환경 이름(기본: config/so101.env 의 SO101_ENV_NAME = so-arm_ws)
#   bash scripts/install.sh --lerobot-ref main   # LeRobot 을 다른 커밋/브랜치로(기본은 검증한 고정 커밋)
#
# 하는 일
#   1) conda 가 없으면 Miniforge 를 ~/miniforge3 에 설치(~/.bashrc 는 고치지 않음)
#   2) NVIDIA 드라이버를 보고 torch 빌드 선택
#        드라이버 >= 580.65 또는 GPU 없음 → torch 2.15.0 (PyPI, CUDA 13)   + ffmpeg 9.0.2
#        드라이버 <  580.65              → torch 2.11.0 (cu128 인덱스)     + ffmpeg 8.1.1
#   3) conda 환경: python 3.12.16 + ffmpeg (conda-forge)
#   4) lerobot/ 에 GitHub huggingface/lerobot 클론 후 고정 커밋으로 체크아웃
#   5) uv 로 torch + lerobot(editable) + 고정 버전(requirements/constraints.txt) 설치
#   6) import 한 번으로 간단 확인
set -euo pipefail
unset PYTHONPATH   # ROS 등 시스템 파이썬 경로가 섞이지 않게

WS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LEROBOT_URL="https://github.com/huggingface/lerobot.git"
LEROBOT_COMMIT="d490e472a5d1a207cfe0255caaaf74b6d66e4656"   # LeRobot 0.7.1 (2026-11-05)
EXTRAS="core_scripts,training,feetech,smolvla,diffusion"
PYTHON_VER="3.12.16"
UV_VER="0.13.7"

ENV_NAME="$(sed -n 's/^SO101_ENV_NAME=//p' "$WS/config/so101.env")"; ENV_NAME="${ENV_NAME:-so-arm_ws}"
TORCH="auto"; DEMO=0; DIALOUT=0; REF=""
while [ $# -gt 0 ]; do
    case "$1" in
        --demo) DEMO=1; shift ;;
        --dialout) DIALOUT=1; shift ;;
        --torch) TORCH="$2"; shift 2 ;;
        --env-name) ENV_NAME="$2"; shift 2 ;;
        --lerobot-ref) REF="$2"; shift 2 ;;
        -h|--help) awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"; exit 0 ;;
        *) echo "알 수 없는 옵션: $1 (--help)" >&2; exit 1 ;;
    esac
done

say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[경고]\033[0m %s\n' "$*" >&2; }

[ "$(uname -m)" = "x86_64" ] || { echo "x86_64 만 지원한다 (현재 $(uname -m))" >&2; exit 1; }
grep -q 'VERSION_ID="24.04"' /etc/os-release 2>/dev/null || warn "Ubuntu 24.04 가 아니다. 계속 진행한다."
command -v git >/dev/null || { echo "git 이 없다: sudo apt-get install -y git" >&2; exit 1; }

# ---- 1) conda ----
CONDA=""
for c in "${CONDA_EXE:-}" "$HOME/miniforge3/bin/conda" "$HOME/miniconda3/bin/conda" "$HOME/anaconda3/bin/conda"; do
    if [ -n "$c" ] && [ -x "$c" ]; then CONDA="$c"; break; fi
done
if [ -z "$CONDA" ]; then
    say "[1/6] Miniforge 설치 → ~/miniforge3"
    tmp="$(mktemp -d)"
    url="https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh"
    if command -v wget >/dev/null; then wget -q -O "$tmp/mf.sh" "$url"; else curl -fsSL -o "$tmp/mf.sh" "$url"; fi
    bash "$tmp/mf.sh" -b -p "$HOME/miniforge3"
    rm -rf "$tmp"
    CONDA="$HOME/miniforge3/bin/conda"
else
    say "[1/6] conda: $CONDA"
fi
PY="$("$CONDA" info --base)/envs/$ENV_NAME/bin/python"

# ---- 2) torch 빌드 선택 ----
if [ "$TORCH" = "auto" ]; then
    TORCH="cu13"
    if command -v nvidia-smi >/dev/null; then
        drv="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 || true)"
        if [ -n "$drv" ] && [ "$(printf '%s\n' "$drv" 580.65 | sort -V | head -1)" != "580.65" ]; then TORCH="cu128"; fi
        echo "NVIDIA 드라이버: ${drv:-?}"
    else
        echo "NVIDIA GPU 없음 → CPU 로 동작(학습은 매우 느림)"
    fi
fi
# TORCH_PKGS 는 TORCH_INDEX 에서, torchcodec 은 항상 PyPI 에서 받는다
# (cu128 인덱스의 torchcodec 은 NVIDIA NPP 라이브러리가 따로 필요해 영상 디코딩이 pyav 로 떨어진다)
case "$TORCH" in
    cu13)  TORCH_PKGS=(torch==2.15.0 torchvision==0.29.2); CODEC=torchcodec==0.17.0; TORCH_INDEX=(); FFMPEG="9.0.2" ;;
    cu128) TORCH_PKGS=(torch==2.11.0 torchvision==0.26.0); CODEC=torchcodec==0.11.1
           TORCH_INDEX=(--index-url https://download.pytorch.org/whl/cu128); FFMPEG="8.1.1" ;;
    *) echo "--torch 는 auto, cu13, cu128 중 하나" >&2; exit 1 ;;
esac
say "[2/6] torch 빌드: $TORCH (${TORCH_PKGS[*]} $CODEC), ffmpeg $FFMPEG"

# ---- 3) conda 환경 ----
if [ ! -x "$PY" ]; then
    say "[3/6] conda 환경 생성: $ENV_NAME"
    "$CONDA" create -y -q -n "$ENV_NAME" -c conda-forge --override-channels "python=$PYTHON_VER" "ffmpeg=$FFMPEG"
else
    say "[3/6] conda 환경 있음: $ENV_NAME ($("$PY" --version))"
fi

# ---- 4) LeRobot 소스 ----
want="${REF:-$LEROBOT_COMMIT}"
if [ ! -d "$WS/lerobot/.git" ]; then
    say "[4/6] LeRobot 클론 → lerobot/ ($want)"
    git clone -q --filter=blob:none "$LEROBOT_URL" "$WS/lerobot"
    git -C "$WS/lerobot" -c advice.detachedHead=false checkout -q "$want"
elif [ -n "$REF" ]; then
    say "[4/6] LeRobot → $REF"
    git -C "$WS/lerobot" fetch -q origin
    git -C "$WS/lerobot" -c advice.detachedHead=false checkout -q "$REF"
else
    cur="$(git -C "$WS/lerobot" rev-parse HEAD)"
    say "[4/6] LeRobot 있음: ${cur:0:8}"
    [ "$cur" = "$LEROBOT_COMMIT" ] || warn "검증한 커밋(${LEROBOT_COMMIT:0:8})과 다르다. 그대로 둔다(맞추려면 --lerobot-ref $LEROBOT_COMMIT)."
fi

# ---- 5) 파이썬 패키지 ----
say "[5/6] 패키지 설치 (uv)"
"$PY" -m pip install -q "uv==$UV_VER"
UV="$(dirname "$PY")/uv"
export UV_LINK_MODE=copy
"$UV" pip install --python "$PY" "${TORCH_INDEX[@]}" "${TORCH_PKGS[@]}"
"$UV" pip install --python "$PY" -c "$WS/requirements/constraints.txt" -e "$WS/lerobot[$EXTRAS]" "${TORCH_PKGS[@]}" "$CODEC"

# ---- 6) 간단 확인 ----
say "[6/6] 확인"
"$PY" -c "import lerobot, torch; print(f'lerobot {lerobot.__version__} | torch {torch.__version__} | CUDA 사용 가능: {torch.cuda.is_available()}')"

if [ $DIALOUT = 1 ] && ! id -nG | tr ' ' '\n' | grep -qx dialout; then
    say "시리얼 포트 권한 (sudo)"
    sudo usermod -aG dialout "$USER" && echo "추가됨. 로그아웃 후 다시 로그인(또는 재부팅)해야 적용된다."
fi
if [ $DEMO = 1 ]; then
    say "예제 데이터셋·모델 받기"
    bash "$WS/scripts/hub.sh" download-dataset jammin0319/so101_ball_to_bowl_v1 --revision 9a4f2b86df9c171c725fbc7c2ce9af37e4b35f08
    bash "$WS/scripts/hub.sh" download-model jammin0319/act_so101_ball_to_bowl_v1 --revision dd639021a17f8e7584baa100d40a5127f72ba14f --step 100000
fi

echo
echo "설치 완료. 새 터미널마다:  source $WS/scripts/activate.sh"
if ! id -nG | tr ' ' '\n' | grep -qx dialout; then
    echo "시리얼 포트 권한이 없다(팔 연결에 필요):  sudo usermod -aG dialout \$USER  → 로그아웃 후 다시 로그인"
fi
[ "$ENV_NAME" = "$(sed -n 's/^SO101_ENV_NAME=//p' "$WS/config/so101.env")" ] || \
    echo "참고: --env-name 을 바꿨다면 config/so101.env 의 SO101_ENV_NAME 도 $ENV_NAME 으로 바꾼다."
