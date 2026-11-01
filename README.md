# RecMac

Free macOS screen recorder that captures system audio. Built with Swift and ScreenCaptureKit.

**Requirements:** Apple silicon, macOS 15 or later.

## Download

[Download RecMac.dmg](https://github.com/snael0510-coder/RecMac/releases/latest/download/RecMac.dmg) · [Website](https://snael0510-coder.github.io/RecMac/)

Open the DMG and drag RecMac to Applications. The app uses a local development certificate. If macOS says “RecMac Not Opened,” click Done, then go to System Settings → Privacy & Security → Open Anyway. Allow Screen & System Audio Recording when prompted.

Recordings are saved in `~/Movies/RecMac/`.

## Build from source

```bash
./make-icon.sh
RECMAC_NO_OPEN=1 ./build.sh
./make-dmg.sh
```

`build.sh` opens the built app unless `RECMAC_NO_OPEN=1` is set. It signs with a local `MacRecorder Dev` certificate when available, or uses an ad hoc signature. `setup-cert.sh` creates the local certificate and a private `.p12` backup; keep that backup private.

## Current limitations

- When recording system and microphone audio together, the file has two audio tracks. Some players play only the first track.
- The app is not notarized, so macOS may require an extra opening step.

## 한국어

RecMac은 맥 내부 소리까지 담는 무료 화면 녹화 앱입니다. Apple 실리콘과 macOS 15 이상이 필요합니다. DMG에서 앱을 응용 프로그램으로 옮기고, 처음 실행할 때 macOS 보안 확인 및 화면·시스템 오디오 녹음 권한을 허용하세요. 녹화 파일은 `~/Movies/RecMac/`에 저장됩니다.
