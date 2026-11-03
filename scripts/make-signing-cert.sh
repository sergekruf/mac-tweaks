#!/bin/bash
# Создаёт самоподписанный сертификат для подписи кода «Mac Tweaks Dev» в связке ключей login.
# Зачем: при ad-hoc подписи macOS привязывает «Мониторинг ввода» к хешу сборки, и разрешение
# слетает после каждой пересборки. С постоянным сертификатом требование подписи одно и то же.
# Доверие сертификату не нужно: codesign подписывает и недоверенным, а TCC сверяет хеш сертификата.
# При первой подписи macOS может спросить, разрешить ли codesign доступ к ключу, — «Разрешать всегда».
set -euo pipefail
NAME="${1:-Mac Tweaks Dev}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning | grep -qF "\"$NAME\""; then
  echo "Сертификат «$NAME» уже есть — ничего не делаю."
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CNF

# 10 лет; пароль p12 одноразовый, нужен только для импорта
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.cnf"
P12PASS=$(uuidgen)
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -name "$NAME" -out "$TMP/cert.p12" -passout "pass:$P12PASS"

# -T: codesign может брать ключ без запроса доступа
security import "$TMP/cert.p12" -k "$KEYCHAIN" -P "$P12PASS" -T /usr/bin/codesign

security find-identity -p codesigning | grep -F "\"$NAME\"" && echo "Готово: «$NAME». Пересоберите ./build.sh --install."
