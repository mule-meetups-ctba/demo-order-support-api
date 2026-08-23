#!/usr/bin/env bash
#
# encrypt-secrets.sh — cifra todos os segredos da demo com a Secure Properties Tool
# e grava os valores ![...] nos secure-config-dev.yaml dos 3 projetos.
#
# Pré-requisitos:
#   - Java 17 no PATH
#   - secure-properties-tool.jar (baixe das docs da MuleSoft) — informe via --jar ou $SP_TOOL
#   - Algoritmo AES/CBC => a chave precisa ter EXATAMENTE 16 caracteres (AES-128)
#
# Uso:
#   # 1) Modo DEMO: cifra valores dummy com a chave DemoMeetupKey016 (faz o mvn test passar)
#   ./encrypt-secrets.sh --demo --jar /caminho/secure-properties-tool.jar
#
#   # 2) Modo REAL: passe seus segredos por variáveis de ambiente
#   export ENC_KEY='SuaChaveDe16Char'
#   export STRIPE_API_KEY='sk_test_...'
#   export OPENAI_API_KEY='sk-...'
#   export ORDERS_CLIENT_SECRET='...'
#   export MCP_CLIENT_SECRET='...'         # contrato agent-to-mcp-server (ver SECURITY-POLICIES.md)
#   export SALESFORCE_PASSWORD='...'
#   export SALESFORCE_TOKEN='...'
#   export SLACK_BOT_TOKEN='xoxb-...'
#   ./encrypt-secrets.sh --jar /caminho/secure-properties-tool.jar
#
# Importante: rode com a MESMA chave que você usará em -Dencryption.key no deploy.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SP_TOOL="${SP_TOOL:-}"
DEMO=false

# ---- parse args ----
while [[ $# -gt 0 ]]; do
  case "$1" in
    --demo) DEMO=true; shift ;;
    --jar)  SP_TOOL="$2"; shift 2 ;;
    --key)  ENC_KEY="$2"; shift 2 ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Argumento desconhecido: $1" >&2; exit 1 ;;
  esac
done

# ---- demo defaults ----
if $DEMO; then
  ENC_KEY="${ENC_KEY:-DemoMeetupKey016}"
  STRIPE_API_KEY="${STRIPE_API_KEY:-sk_test_dummy}"
  OPENAI_API_KEY="${OPENAI_API_KEY:-sk-dummy}"
  ORDERS_CLIENT_SECRET="${ORDERS_CLIENT_SECRET:-dummy}"
  MCP_CLIENT_SECRET="${MCP_CLIENT_SECRET:-dummy}"
  SALESFORCE_PASSWORD="${SALESFORCE_PASSWORD:-dummy}"
  SALESFORCE_TOKEN="${SALESFORCE_TOKEN:-dummy}"
  SLACK_BOT_TOKEN="${SLACK_BOT_TOKEN:-xoxb-dummy}"
fi

# ---- validations ----
command -v java >/dev/null 2>&1 || { echo "ERRO: Java não encontrado no PATH." >&2; exit 1; }
[[ -n "${SP_TOOL}" ]] || { echo "ERRO: informe a tool com --jar <path> ou \$SP_TOOL." >&2; exit 1; }
[[ -f "${SP_TOOL}" ]] || { echo "ERRO: jar não encontrado: ${SP_TOOL}" >&2; exit 1; }
: "${ENC_KEY:?ERRO: defina a chave com --key, \$ENC_KEY ou use --demo}"
if [[ ${#ENC_KEY} -ne 16 ]]; then
  echo "ERRO: AES-128 exige chave de 16 caracteres (a sua tem ${#ENC_KEY})." >&2
  exit 1
fi

require() { # require VARNAME "rótulo amigável"
  local v="${!1:-}"
  [[ -n "$v" ]] || { echo "ERRO: variável $1 ($2) não definida. Veja o cabeçalho do script." >&2; exit 1; }
}
require STRIPE_API_KEY        "Stripe API key"
require OPENAI_API_KEY        "OpenAI API key"
require ORDERS_CLIENT_SECRET  "client_secret do contrato mcp-server-to-orders-api"
require MCP_CLIENT_SECRET     "client_secret do contrato agent-to-mcp-server"
require SALESFORCE_PASSWORD   "senha Salesforce"
require SALESFORCE_TOKEN      "security token Salesforce"
require SLACK_BOT_TOKEN       "Slack bot token"

# ---- cifra uma string e retorna apenas o valor cifrado ----
enc() {
  java -cp "${SP_TOOL}" com.mulesoft.tools.SecurePropertiesTool string encrypt AES CBC "${ENC_KEY}" "$1" | tr -d '\r\n'
}

HEADER="# Segredos CIFRADOS (Secure Configuration Properties module) — gerado por encrypt-secrets.sh.
# NUNCA commitar valores em texto puro. Apenas o resultado cifrado entre ![ ... ].
# Cifrado com AES/CBC; use a MESMA chave em -Dencryption.key no deploy."

write_yaml() { # write_yaml <arquivo> <conteúdo>
  printf '%s\n%s\n' "$HEADER" "$2" > "$1"
  echo "  -> $1"
}

echo "Cifrando segredos (AES/CBC, chave de 16 chars)..."

# demo-order-support-api
E_STRIPE="$(enc "$STRIPE_API_KEY")"
write_yaml "${SCRIPT_DIR}/demo-order-support-api/src/main/resources/secure-config-dev.yaml" \
"stripe:
  api:
    key: \"![${E_STRIPE}]\""

# demo-support-agent
E_OPENAI="$(enc "$OPENAI_API_KEY")"
E_MCP_CLIENT="$(enc "$MCP_CLIENT_SECRET")"
write_yaml "${SCRIPT_DIR}/demo-support-agent/src/main/resources/secure-config-dev.yaml" \
"openai:
  api:
    key: \"![${E_OPENAI}]\"
mcp:
  clientSecret: \"![${E_MCP_CLIENT}]\""

# demo-support-mcp-server
E_ORDERS="$(enc "$ORDERS_CLIENT_SECRET")"
E_SF_PWD="$(enc "$SALESFORCE_PASSWORD")"
E_SF_TOK="$(enc "$SALESFORCE_TOKEN")"
E_SLACK="$(enc "$SLACK_BOT_TOKEN")"
write_yaml "${SCRIPT_DIR}/demo-support-mcp-server/src/main/resources/secure-config-dev.yaml" \
"orders:
  clientSecret: \"![${E_ORDERS}]\"
stripe:
  api:
    key: \"![${E_STRIPE}]\"
salesforce:
  password: \"![${E_SF_PWD}]\"
  token: \"![${E_SF_TOK}]\"
slack:
  bot:
    token: \"![${E_SLACK}]\""

echo "OK. Lembre de fazer deploy com -Dencryption.key=${ENC_KEY} (não commite a chave)."
