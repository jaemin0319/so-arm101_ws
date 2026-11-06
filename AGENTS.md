# 에이전트 지시 (Claude Code / Codex 공통)

이 레포는 SO-ARM101(SO-101) 모방학습 작업 공간이다. 사용자가 레포 링크를 주고 "설치/세팅해줘" 라고 하면 아래만 한다.
설치는 빨리 끝내는 것이 목표다. **아래에 없는 검증(학습 시험, 데이터 다운로드, 장치 점검, 전체 테스트)은 사용자가 요청할 때만** 한다.

## 설치 순서 (Ubuntu 24.04 x86_64)

1. `git` 이 없으면 사용자에게 `sudo apt-get install -y git` 를 직접 실행해 달라고 한다(비밀번호 필요).
2. 받기. 이미 `~/SO-ARM_ws` 가 있으면 `git -C ~/SO-ARM_ws pull` 만 한다.
   ```bash
   git clone https://github.com/jaemin0319/so-arm101_ws.git ~/SO-ARM_ws
   ```
3. 설치. 5~10분 걸리고 인터넷이 필요하다(약 4 GB 다운로드). 타임아웃을 넉넉히(15분 이상) 잡거나 백그라운드로 실행한다.
   ```bash
   bash ~/SO-ARM_ws/scripts/install.sh
   ```
   - conda 가 없으면 Miniforge 를 `~/miniforge3` 에 자동 설치한다. `~/.bashrc` 는 고치지 않는다.
   - NVIDIA 드라이버 버전을 보고 torch 빌드를 자동으로 고른다. 따로 지정하지 않는다.
   - 마지막 줄의 `lerobot ... | torch ... | CUDA 사용 가능: ...` 가 나오면 성공이다.
4. 시리얼 포트 권한: `id -nG | grep -w dialout` 로 확인하고, 없으면 사용자에게 아래를 직접 실행한 뒤 로그아웃·재로그인하라고 안내한다(sudo 비밀번호가 필요하므로 대신 우회하지 않는다).
   ```bash
   sudo usermod -aG dialout $USER
   ```
5. 끝. 사용자에게 알려 줄 것:
   - 새 터미널마다 `source ~/SO-ARM_ws/scripts/activate.sh`
   - 사용법은 `README.md` (보정 → 텔레옵 → 녹화 → 학습 → 추론)
   - 팔·카메라가 레포 작성자와 다르면 README 의 "다른 PC·다른 팔에서" 절대로 `config/so101.env` 를 고친다

## 하지 않는 것

- `~/.bashrc`, 시스템 파이썬, apt 패키지(git 제외)를 건드리지 않는다.
- `lerobot/` 소스를 다른 커밋으로 바꾸지 않는다(검증한 커밋으로 고정돼 있다).
- `config/so101.env`, `calibration/` 은 사용자가 요청할 때만 고친다.
- 설치 실패 시 패키지를 임의로 다른 버전으로 바꾸지 말고, 오류 메시지와 함께 사용자에게 알린다.

## 작업 공간 규칙 (설치 이후 작업할 때)

- 모든 작업은 `scripts/*.sh` 로 한다. `--dry-run`(명령만 출력), `--check`(장치 없이 LeRobot 설정 해석)를 지원한다.
- 장치 경로·ID·카메라 설정은 `config/so101.env` 하나에만 있다. 스크립트에 값을 직접 쓰지 않는다.
- 데이터셋은 `data/`, 받은 모델은 `models/`, 학습 결과는 `outputs/train/<job>/` (모두 git 제외).
