#!/usr/bin/env bash
#
# encrypt-secrets.sh — cifra os segredos DESTE projeto com a Secure Properties Tool
# e grava os valores ![...] em src/main/resources/secure-config-dev.yaml.
#
# Pré-requisitos:
#   - Java 17 no PATH
#   - secure-properties-tool.jar (baixe das docs da MuleSoft) — via --jar ou $SP_TOOL
#   - AES/CBC => a chave precisa ter EXATAMENTE 16 caracteres (AES-128)
#
# Uso:
#   export ENC_KEY='SuaChaveDe16Char'
#   export STRIPE_API_KEY='...'   # Stripe API key
#   ./scripts/encrypt-secrets.sh --jar /caminho/secure-properties-tool.jar
#
#   # ou, para valores dummy que fazem o mvn test passar:
#   ./scripts/encrypt-secrets.sh --demo --jar /caminho/secure-properties-tool.jar
#
# Importante: use a MESMA chave em -Dencryption.key no deploy.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TARGET="${PROJECT_DIR}/src/main/resources/secure-config-dev.yaml"
SP_TOOL="${SP_TOOL:-}"
DEMO=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --demo) DEMO=true; shift ;;
    --jar)  SP_TOOL="$2"; shift 2 ;;
    --key)  ENC_KEY="$2"; shift 2 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Argumento desconhecido: $1" >&2; exit 1 ;;
  esac
done

if $DEMO; then
  ENC_KEY="${ENC_KEY:-DemoMeetupKey016}"
  STRIPE_API_KEY="${STRIPE_API_KEY:-sk_test_dummy}"
fi

command -v java >/dev/null 2>&1 || { echo "ERRO: Java não encontrado no PATH." >&2; exit 1; }
[[ -n "${SP_TOOL}" ]] || { echo "ERRO: informe a tool com --jar <path> ou \$SP_TOOL." >&2; exit 1; }
[[ -f "${SP_TOOL}" ]] || { echo "ERRO: jar não encontrado: ${SP_TOOL}" >&2; exit 1; }
: "${ENC_KEY:?ERRO: defina a chave com --key, \$ENC_KEY ou use --demo}"
if [[ ${#ENC_KEY} -ne 16 ]]; then
  echo "ERRO: AES-128 exige chave de 16 caracteres (a sua tem ${#ENC_KEY})." >&2
  exit 1
fi

require() {
  local v="${!1:-}"
  [[ -n "$v" ]] || { echo "ERRO: variável $1 ($2) não definida. Veja o cabeçalho do script." >&2; exit 1; }
}
require STRIPE_API_KEY         "Stripe API key"

enc() {
  java -cp "${SP_TOOL}" com.mulesoft.tools.SecurePropertiesTool string encrypt AES CBC "${ENC_KEY}" "$1" | tr -d '\r\n'
}

echo "Cifrando segredos de demo-order-support-api (AES/CBC)..."
E_STRIPE="$(enc "$STRIPE_API_KEY")"
cat > "${TARGET}" <<EOF
# Segredos CIFRADOS (Secure Configuration Properties module) — gerado por scripts/encrypt-secrets.sh.
# NUNCA commitar valores em texto puro. Apenas o resultado cifrado entre ![ ... ].
# Cifrado com AES/CBC; use a MESMA chave em -Dencryption.key no deploy.
stripe:
  api:
    key: "![${E_STRIPE}]"
EOF

echo "  -> ${TARGET}"
echo "OK. Faça o deploy com -Dencryption.key=<sua chave> (não commite a chave)."
