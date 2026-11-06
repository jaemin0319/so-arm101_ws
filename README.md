# so-arm101_ws

SO-ARM101(SO-101) 모방학습을 **한 작업 공간에서** 처음부터 끝까지 하는 레포.
보정·카메라 → 텔레옵 → 데이터 녹화/업로드/다운로드 → 학습/업로드/다운로드 → 로봇에서 추론까지 모두 `scripts/` 로 한다.

- LeRobot: GitHub `huggingface/lerobot` 을 `lerobot/` 에 클론해 editable 설치. 검증한 커밋 `d490e472`(0.7.1, 2026-11-05)로 고정
- conda 환경 `so-arm_ws`: Python 3.12.16, PyTorch(드라이버에 맞춰 자동 선택), conda-forge ffmpeg
- 패키지 버전: `requirements/constraints.txt` 로 고정(작성자 PC에서 설치·학습·추론까지 확인한 버전)

## 설치 (Ubuntu 24.04 x86_64)

```bash
sudo apt-get install -y git                                            # git 이 없을 때만
git clone https://github.com/jaemin0319/so-arm101_ws.git ~/SO-ARM_ws
bash ~/SO-ARM_ws/scripts/install.sh                                    # 5~10분, 약 4 GB 다운로드
sudo usermod -aG dialout $USER                                         # 시리얼 포트 권한(한 번) → 로그아웃 후 다시 로그인
```

- conda 가 없으면 Miniforge 를 `~/miniforge3` 에 자동 설치한다. `~/.bashrc` 는 고치지 않는다.
- NVIDIA 드라이버 **580.65 이상**(또는 GPU 없음)이면 torch 2.15.0(CUDA 13), **그보다 낮으면** torch 2.11.0(CUDA 12.8)을 자동으로 고른다. CUDA Toolkit 은 따로 필요 없다.
- 옵션: `--demo`(예제 데이터셋 454 MB·모델 198 MB 받기), `--dialout`(위 sudo 명령 대신 실행), `--torch cu13|cu128`(강제), `--env-name`.
- 다시 실행해도 안전하다(있는 것은 건너뛴다).

**AI 에이전트에게 맡길 때:** Claude Code 나 Codex 에 `https://github.com/jaemin0319/so-arm101_ws 설치해줘` 라고만 하면 된다. 에이전트 지시는 [AGENTS.md](AGENTS.md)(Claude Code 는 [CLAUDE.md](CLAUDE.md) 가 같은 내용을 불러옴)에 있다.

## 폴더

```
SO-ARM_ws/
├── config/so101.env      ← 포트·ID·카메라·저장 위치·녹화/학습 기본값 (장치가 바뀌면 여기만 고친다)
├── calibration/          ← LeRobot 보정 파일 (robots/so_follower/*.json, teleoperators/so_leader/*.json)
├── scripts/              ← 모든 작업 스크립트 (아래 표)
├── requirements/         ← 고정 패키지 버전
├── lerobot/              ← (설치 때 생성) LeRobot 소스
├── data/                 ← (git 제외) 데이터셋. 녹화: data/<user>/<name>, 허브에서 받은 것: data/hub/
├── models/               ← (git 제외) 허브에서 받은 모델: models/<repo 이름>/
└── outputs/              ← (git 제외) 학습 결과 outputs/train/<job>/, 카메라 사진 outputs/cameras/
```

## 0. 새 터미널마다

```bash
source ~/SO-ARM_ws/scripts/activate.sh     # conda 환경 + config/so101.env 불러오기
cd ~/SO-ARM_ws
```

`scripts/*.sh` 는 이걸 알아서 하므로 스크립트만 쓸 때는 생략해도 된다. `lerobot-*` 명령이나 `python scripts/*.py` 를 직접 쓸 때는 필요하다.
모든 `.sh` 는 `--help`, `--dry-run`(명령만 출력), `--check`(장치를 열지 않고 LeRobot 이 해석한 설정만 출력)를 지원하고, `--` 뒤의 인자는 lerobot 명령에 그대로 넘긴다.

## 다른 PC·다른 팔에서

`config/so101.env` 와 `calibration/` 은 레포 작성자의 장치(2026-10-23 실측) 값이다. 같은 팔·같은 노트북이면 그대로 쓰고, 다르면 아래 순서로 바꾼다.

1. **팔 포트**: 팔 USB 를 꽂고 `ls -l /dev/serial/by-id/` → 두 보드의 경로를 `SO101_FOLLOWER_PORT`, `SO101_LEADER_PORT` 에 넣는다.
   어느 쪽이 어느 팔인지 모르면 `lerobot-find-port`(한쪽 케이블을 뽑았다 꽂으면 그 포트를 알려 줌).
2. **카메라**: `python scripts/cameras.py list` → `python scripts/cameras.py snap --all` 로 찍힌 사진을 보고 front/wrist 경로를 `SO101_CAM_FRONT`, `SO101_CAM_WRIST` 에 넣는다.
   USB 시리얼이 같은 카메라 2대는 `/dev/v4l/by-id` 가 섞이므로 `/dev/v4l/by-path`(USB 포트 위치) 를 쓴다.
3. **보정**: 다른 팔이면 `bash scripts/calibrate.sh follower`, `bash scripts/calibrate.sh leader`. (새로 조립한 팔은 먼저 `bash scripts/setup_motors.sh follower|leader`)
4. **Hugging Face 사용자**: 업로드할 계정으로 `HF_USER` 를 바꾸고 `bash scripts/hub.sh login`.

## 1. 장치 연결 확인

작성자 PC의 USB 허브 배치: **2.1 = wrist 카메라, 2.2 = follower, 2.3 = leader, 2.4 = front 카메라** (같은 구멍에 꽂아야 카메라 경로가 유지된다). follower 는 12V, leader 는 5V 전원.

```bash
bash scripts/check_devices.sh          # 포트·카메라·권한·보정 파일 확인 (장치를 열지 않음)
python scripts/check_env.py            # 소프트웨어·GPU 점검
```

## 2. 카메라

```bash
python scripts/cameras.py list         # 연결된 카메라(by-path)와 front/wrist 대응
python scripts/cameras.py live         # 실시간 창 (s = 저장, q = 종료)
python scripts/cameras.py live --overlay jammin0319/so101_ball_to_bowl_v1
                                       # 학습 데이터의 front 화면을 반투명으로 겹쳐(o 로 켜고 끔) 카메라 위치를 학습 때와 맞춘다
python scripts/cameras.py snap         # front/wrist 한 장씩 → outputs/cameras/
python scripts/cameras.py snap --all   # 연결된 모든 카메라 한 장씩 (front/wrist 경로 찾기)
```

- 설정: 640×480, 30fps, **MJPG**(필수 — YUYV 는 USB 2.0 허브 대역폭 부족으로 프레임이 깨짐), front 180° 회전.
- 카메라는 한 프로그램만 열 수 있다. 창을 닫고 teleop/record/rollout 을 실행한다.

## 3. 포트·모터·보정

```bash
bash scripts/calibrate.sh follower     # 보정 → calibration/robots/so_follower/so101_follower.json
bash scripts/calibrate.sh leader       # 보정 → calibration/teleoperators/so_leader/so101_leader.json
bash scripts/setup_motors.sh follower  # (새 팔/모터 교체 때만) 모터 ID 설정
```

- 기존 보정 파일이 있으면 LeRobot 이 묻는다: **Enter = 기존 파일 사용**, `c` + Enter = 새로 보정. 새로 보정하면 이전 파일은 `calibration/backup/` 에 자동 백업된다.
- 연결할 때 "Mismatch between calibration values ..." 가 뜨면 모터에 저장된 값과 파일이 다른 것이다. Enter 를 누르면 파일 값을 모터에 쓴다.

## 4. 텔레옵 (leader → follower)

```bash
bash scripts/teleop.sh                 # 팔만
bash scripts/teleop.sh --display       # 카메라까지 열고 Rerun 창에 영상·관절값 표시
```

Ctrl+C 로 멈추면 follower 토크가 꺼져 팔이 힘없이 내려온다. **손으로 받친다.**

## 5. 데이터셋 만들기·올리기·받기

```bash
# 녹화 (로컬 data/<HF_USER>/ball_to_bowl_v2 에 저장)
bash scripts/record.sh --name ball_to_bowl_v2 --task "Pick up the ball and place it in the bowl" --episodes 20
# 같은 데이터셋에 10개 더
bash scripts/record.sh --name ball_to_bowl_v2 --task "Pick up the ball and place it in the bowl" --episodes 10 --resume
# 녹화 옵션: --episode-time 30 --reset-time 10 --display --push(끝나면 업로드) --private

bash scripts/replay.sh --dataset ball_to_bowl_v2 --episode 0      # follower 로 다시 재생
lerobot-dataset-viz --repo-id <HF_USER>/ball_to_bowl_v2 --episode-index 0 --root data/<HF_USER>/ball_to_bowl_v2   # Rerun 으로 보기

bash scripts/hub.sh login                                         # (처음 한 번) 업로드용 로그인
bash scripts/hub.sh upload-dataset ball_to_bowl_v2 [--private]    # 허브에 올리기
bash scripts/hub.sh download-dataset jammin0319/so101_ball_to_bowl_v1 [--revision <commit>]   # 허브에서 받기
bash scripts/hub.sh list                                          # 로컬 데이터셋·모델 목록
```

- 녹화 중 키(터미널이 포커스된 상태): **→ / n** = 이번 에피소드 끝내고 다음, **← / r** = 이번 에피소드 다시, **ESC / q** = 종료.
- 이름에 `/` 가 없으면 `config` 의 `HF_USER` 가 앞에 붙는다.
- 녹화 기본값(fps 30, 에피소드 30초, 정리 10초)은 `config/so101.env` 의 `SO101_RECORD_*`.

## 6. 학습·올리기·모델 받기

```bash
bash scripts/train.sh --dataset ball_to_bowl_v2 --job act_ball_v2                 # ACT, 100k step, batch 8
bash scripts/train.sh --dataset ball_to_bowl_v2 --job act_ball_v2 --push act_ball_v2   # 끝나면 허브 업로드
bash scripts/train.sh --job act_ball_v2 --resume                                  # 끊긴 학습 이어서
bash scripts/train.sh --dataset ball_to_bowl_v2 --job act_ft --from models/act_so101_ball_to_bowl_v1/checkpoints/100000/pretrained_model   # 기존 모델에서 fine-tune
bash scripts/train.sh --dataset ball_to_bowl_v2 --job dp_v2 --policy diffusion    # 다른 정책
bash scripts/train.sh ... --trackio                                               # 학습 곡선 (보기: trackio show --project lerobot)
bash scripts/train.sh ... -- --policy.chunk_size=50 --num_workers=4               # lerobot-train 인자 직접 추가

bash scripts/hub.sh upload-model act_ball_v2 <HF_USER>/act_ball_v2 [--private]   # 학습 결과(last) 업로드
bash scripts/hub.sh download-model jammin0319/act_so101_ball_to_bowl_v1 --step 100000   # 모델 받기 → models/
```

- 결과: `outputs/train/<job>/checkpoints/<step>/pretrained_model` (마지막은 `checkpoints/last`). step·batch·저장 간격 기본값은 `config/so101.env` 의 `SO101_TRAIN_*`.
- 작성자 PC(RTX 5060 Laptop 8GB)에서 ACT batch 4 기준 약 6 step/s, GPU 메모리 2.2 GB.
- `download-model` 은 optimizer 상태(`training_state`)를 기본으로 받지 않는다. 이어서 학습할 거면 `--with-optimizer`.

## 7. 추론 (로봇에서 정책 실행)

```bash
# 로봇 없이 먼저 점검: 데이터셋 에피소드를 넣어 예측 action 을 정답과 비교 + 추론 시간
python scripts/check_policy.py --policy act_ball_v2 --dataset ball_to_bowl_v2
python scripts/check_policy.py --policy act_so101_ball_to_bowl_v1 --dataset jammin0319/so101_ball_to_bowl_v1

# 로봇에서 실행 (Ctrl+C 로 종료 → 팔이 시작 자세로 천천히 돌아간다)
bash scripts/rollout.sh --policy act_ball_v2                              # 학습한 모델 (outputs/train/act_ball_v2)
bash scripts/rollout.sh --policy act_so101_ball_to_bowl_v1 --step 100000  # 받은 모델 (models/...)
bash scripts/rollout.sh --policy jammin0319/act_so101_ball_to_bowl_v1 --step 100000   # 허브 repo → models/ 로 받은 뒤 실행
```

| 옵션 | 뜻 |
|---|---|
| `--n-action-steps 20` | ACT 는 한 번에 100개(chunk)를 예측. 그중 N 개 실행 후 다시 추론(기본 100 = 3.3초마다, 20 = 0.67초마다) |
| `--ensemble [0.01]` | 매 프레임 추론 + 겹치는 예측 가중 평균. 반응 빠르고 부드러움 |
| `--duration 60` | 60초 뒤 종료(기본 0 = 무제한) |
| `--task "..."` | 작업 문장. 비우면 학습 데이터셋의 작업 문장을 찾아 쓴다(ACT 는 무시, SmolVLA 등은 필요) |
| `--record NAME --episodes 10` | 실행을 데이터셋 `<HF_USER>/rollout_NAME` 으로 기록(평가용, episodic) |
| `--display` | Rerun 창에 카메라·관절값·action 표시 |
| `--check` | 로봇을 열지 않고 해석된 설정(n_action_steps, 카메라 MJPG·회전 등)만 출력 |

## 예제 데이터·모델 (`install.sh --demo`)

| 종류 | 받는 위치 | 작성자 PC 확인 결과 |
|---|---|---|
| 데이터셋 `jammin0319/so101_ball_to_bowl_v1` @ `9a4f2b86` (100 에피소드, 45,467 프레임, "Pick up the ball and place it in the bowl") | `data/hub/` | AV1 영상 디코딩 OK |
| 모델 `jammin0319/act_so101_ball_to_bowl_v1` @ `dd639021`, ACT 체크포인트 100000 | `models/act_so101_ball_to_bowl_v1/checkpoints/100000/pretrained_model` | 에피소드 0 관절 평균 오차 2.76°, 추론 median 2.5 ms(ensemble 15.3 ms) |

다른 체크포인트(020000~140000): `bash scripts/hub.sh download-model jammin0319/act_so101_ball_to_bowl_v1 --step 140000`

## 설정 파일 `config/so101.env`

| 값 | 내용 |
|---|---|
| `HF_USER` | 허브 사용자. repo 이름 앞에 붙는다 |
| `SO101_FOLLOWER_PORT` / `SO101_LEADER_PORT` | `/dev/serial/by-id/...` (보드 시리얼 번호 기준, 어느 USB 구멍이든 같음) |
| `SO101_FOLLOWER_ID` / `SO101_LEADER_ID` | 보정 파일 이름 (`so101_follower`, `so101_leader`) |
| `SO101_CAM_FRONT` / `SO101_CAM_WRIST` | `/dev/v4l/by-path/...` (USB 포트 위치 기준) |
| `SO101_CAM_*` | 640×480, 30fps, MJPG, front 회전 180 |
| `HF_LEROBOT_HOME` / `HF_LEROBOT_CALIBRATION` | `data/`, `calibration/` (LeRobot 이 읽는 환경 변수) |
| `SO101_RECORD_*`, `SO101_TRAIN_*` | 녹화·학습 기본값 |

## 스크립트

| 스크립트 | 하는 일 |
|---|---|
| `install.sh` | 설치(Miniforge·conda 환경·LeRobot·패키지) |
| `activate.sh` | (source) conda 환경 + 설정 |
| `check_env.py` / `check_devices.sh` | 소프트웨어·GPU 점검 / 포트·카메라·권한 점검 |
| `cameras.py` | 카메라 목록·사진·실시간 창·학습 화면 겹치기 |
| `calibrate.sh` / `setup_motors.sh` | 보정 / 모터 ID 설정 |
| `teleop.sh` | leader → follower |
| `record.sh` / `replay.sh` | 데이터 녹화 / 재생 |
| `hub.sh` | 로그인, 데이터셋·모델 받기/올리기, 로컬 목록 |
| `train.sh` | 학습 (새로, 이어서, fine-tune) |
| `check_policy.py` | 로봇 없이 정책 점검 |
| `rollout.sh` | 로봇에서 정책 실행(+ 기록) |

## 문제 해결

| 증상 | 해결 |
|---|---|
| `conda: command not found` | `source ~/SO-ARM_ws/scripts/activate.sh` (conda init 없이 동작) |
| `CUDA 사용 가능: False` (NVIDIA GPU 있음) | `nvidia-smi` 확인. 드라이버를 올리거나(`sudo ubuntu-drivers install`) `bash scripts/install.sh --torch cu128` |
| `경로가 없다: /dev/serial/...` | 팔 USB·전원 확인. `bash scripts/check_devices.sh`. 다른 팔이면 "다른 PC·다른 팔에서" |
| 포트는 있는데 열리지 않음 | `dialout` 그룹: `sudo usermod -aG dialout $USER` 후 재로그인 |
| 카메라 화면이 깜빡이고 깨짐 | `SO101_CAM_FOURCC=MJPG` 확인(카메라 2대가 USB 2.0 허브 공유) |
| 재부팅 후 front/wrist 가 바뀜 | by-path 경로를 쓰고 같은 허브 구멍에 꽂는다. `python scripts/cameras.py snap --all` 로 확인 |
| `Failed to open OpenCVCamera` | 다른 프로그램이 카메라 사용 중. `fuser -v /dev/video*` |
| `Record loop is running slower (29.8 Hz)` | 한 바퀴가 33.3 ms 를 조금 넘은 것. 가끔이면 무시 |
| 모델 동작이 조금씩 빗나감 | `cameras.py live --overlay <학습 데이터셋>` 으로 카메라 위치를 학습 때와 맞춘다. 보정 차이도 의심 |
| 데이터셋을 hub 캐시로 또 받음 | `hf download --local-dir` 로 받은 폴더는 LeRobot 0.7 이 무시한다. `scripts/hub.sh download-dataset` 사용 |
| Hugging Face 업로드 실패 | `bash scripts/hub.sh whoami` → `login` |

## 참고

- 포트·카메라·보정 값의 출처: [jaemin0319/so101-ws](https://github.com/jaemin0319/so101-ws) (LeRobot 0.6.1 기반 이전 작업 공간). 그 레포의 0.6.1 모델·데이터셋은 이 작업 공간(0.7.1)에서 그대로 로드·추론되는 것을 확인했다.
- LeRobot 0.7 에서 바뀐 점: Feetech 모터 드라이버가 rustypot 으로 바뀜(보정 파일 형식은 같음), wandb → trackio, `lerobot-record` 는 이름 뒤에 날짜를 붙임(`record.sh` 는 `--dataset.no_stamp=true` 로 이름 그대로 저장), 허브 데이터셋은 `data/hub/` 리비전 캐시에 저장.
