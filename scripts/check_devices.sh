#!/usr/bin/env bash
# 장치 점검(장치를 열지 않음): 시리얼 포트·카메라 목록, 권한, config/so101.env 경로가 실제로 있는지.
#   bash scripts/check_devices.sh
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
set +e

ok()   { printf '  \033[32mOK\033[0m   %s\n' "$*"; }
bad()  { printf '  \033[31mFAIL\033[0m %s\n' "$*"; fails=$((fails+1)); }
fails=0

echo "== 사용자 그룹 (시리얼 포트 접근에 dialout 필요)"
if id -nG | tr ' ' '\n' | grep -qx dialout; then ok "$(id -un) ∈ dialout"
else bad "$(id -un) 이 dialout 그룹이 아니다 → sudo usermod -aG dialout $(id -un) 후 재로그인"; fi

echo "== 시리얼 포트 (/dev/serial/by-id)"
if ls /dev/serial/by-id/ >/dev/null 2>&1; then
    for p in /dev/serial/by-id/*; do echo "  $p -> $(readlink -f "$p")"; done
else
    echo "  (없음 — 팔 USB 가 연결되지 않음)"
fi

echo "== 카메라 (/dev/v4l/by-path, video-index0)"
found=0
for p in /dev/v4l/by-path/*video-index0; do
    [ -e "$p" ] || continue
    case "$p" in *-usbv2-*) continue ;; esac
    dev="$(readlink -f "$p")"; name="$(cat "/sys/class/video4linux/$(basename "$dev")/name" 2>/dev/null)"
    echo "  $p -> $dev [$name]"; found=1
done
[ $found = 0 ] && echo "  (없음)"

echo "== config/so101.env 경로"
chk() {
    local label="$1" path="$2"
    if [ -e "$path" ]; then
        if [ -r "$path" ] && [ -w "$path" ]; then ok "$label: $path"
        else bad "$label: $path (권한 없음: $(stat -c '%A %U:%G' "$(readlink -f "$path")"))"; fi
    else bad "$label: $path (없음)"; fi
}
chk "follower" "$SO101_FOLLOWER_PORT"
chk "leader  " "$SO101_LEADER_PORT"
chk "front   " "$SO101_CAM_FRONT"
chk "wrist   " "$SO101_CAM_WRIST"

echo "== 보정 파일"
for f in "$HF_LEROBOT_CALIBRATION/robots/so_follower/$SO101_FOLLOWER_ID.json" \
         "$HF_LEROBOT_CALIBRATION/teleoperators/so_leader/$SO101_LEADER_ID.json"; do
    [ -f "$f" ] && ok "${f#"$SO101_WS"/}" || bad "${f#"$SO101_WS"/} 없음 → bash scripts/calibrate.sh"
done

echo "== 카메라를 쓰고 있는 프로세스"
if command -v fuser >/dev/null; then
    users="$(fuser /dev/video* 2>/dev/null)"
    [ -n "$users" ] && fuser -v /dev/video* 2>&1 | sed 's/^/  /' || echo "  (없음)"
fi

echo
[ $fails = 0 ] && echo "모두 OK" || echo "FAIL $fails 개 — 장치를 연결/전원 확인 후 다시 실행"
exit $fails
