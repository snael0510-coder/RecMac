#!/bin/bash
# 내 맥에서만 쓰는 무료 코드 서명 인증서("MacRecorder Dev")를 만든다. 한 번만 실행하면 된다.
set -euo pipefail
cd "$(dirname "$0")"
NAME="MacRecorder Dev"

if security find-identity -p codesigning 2>/dev/null | grep -q "$NAME"; then
    echo "이미 인증서가 있어요: $NAME"
    exit 0
fi

TMP="$(mktemp -d)"
cat > "$TMP/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF

/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -config "$TMP/cert.cnf" -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$NAME" -out "$TMP/cert.p12" -passout pass:macrecorder

security import "$TMP/cert.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
    -P macrecorder -T /usr/bin/codesign

# 백업용 사본 (잃어버리면 사용자들이 권한을 다시 허용해야 함. 남에게 공유하지 말 것)
cp "$TMP/cert.p12" "./MacRecorder-Dev-backup.p12"
rm -rf "$TMP"

echo ""
echo "인증서 생성 완료: $NAME"
echo "백업 파일: MacRecorder-Dev-backup.p12 (비밀번호: macrecorder)"
