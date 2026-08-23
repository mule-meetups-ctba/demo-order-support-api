# demo-order-support-api

API REST de pedidos da TechWave Electronics (demo do MuleSoft Meetup). Catálogo em memória
enriquecido com o **status real do pagamento no Stripe** (test mode).

- **Runtime:** Mule 4.12 · Java 17 · CloudHub 2.0
- **Governada por:** Client ID Enforcement + Rate Limiting no ingress Omni Gateway

> Parte de uma demo com 4 repositórios. Arquitetura, walkthrough completo, políticas de gateway
> e roteiro de apresentação: **`meetup-omni-material`**.

Esta é a peça que prova um ponto da demo: **agentes não substituem APIs, eles consomem APIs.**
Toda a governança de API Manager que você já conhece continua valendo.

## Endpoints

| Endpoint | Método | Retorna |
|---|---|---|
| `/api/orders/{orderId}` | GET | pedido + cliente + itens + status do pagamento |
| `/api/health` | GET | liveness check |

Pedidos do catálogo: `TW-1001`, `TW-1002`, `TW-1003`. Qualquer outro id devolve `404` com
`{ "error": "ORDER_NOT_FOUND" }`.

## O campo que sustenta o guardrail

A resposta traz `payment.refunded`, calculado a partir do estado **real** no Stripe — não
guardado em banco:

```json
"payment": {
  "paymentIntentId": "pi_...",
  "status": "succeeded",
  "amount": 379.00,
  "currency": "BRL",
  "refunded": false
}
```

É esse campo que permite ao agente recusar um segundo reembolso do mesmo pedido. Sem ele, o
guardrail não teria em que se apoiar.

## Dados de teste no Stripe

Cada pedido precisa de um PaymentIntent confirmado. Crie os seus e substitua os ids `pi_...`
no catálogo em `src/main/mule/order-support-api.xml`:

```bash
# TW-1001 (8990) · TW-1002 (37900) · TW-1003 (11900)
curl https://api.stripe.com/v1/payment_intents -u "sk_test_SUAKEY:" \
  -d amount=8990 -d currency=brl -d "payment_method=pm_card_visa" \
  -d confirm=true -d "automatic_payment_methods[enabled]=true" \
  -d "automatic_payment_methods[allow_redirects]=never"
```

## Build e deploy

```bash
mvn clean test                      # testes
mvn clean deploy -DskipTests        # 1) publica no Exchange
mvn mule:deploy -DmuleDeploy -DskipTests \
  -Dconnected.app.client.id=<CLIENT_ID> \
  -Dconnected.app.client.secret=<CLIENT_SECRET> \
  -Danypoint.org.id=<ORG_ID> \
  -Ddeploy.target=<space ou região> \
  -Denvironment=Sandbox \
  -Dencryption.key=<CHAVE_16_CHARS>
```

Segredo único: `stripe.api.key` (cifrado em `secure-config-dev.yaml`). Ver [SECRETS.md](SECRETS.md).

## Testando

```bash
curl https://<ingress-gw>/api/orders/TW-1001 \
  -H "client_id: ..." -H "client_secret: ..." | jq

# Rate Limiting da demo (5 req/min): a 6ª chamada no mesmo minuto devolve 429
for i in $(seq 1 6); do
  curl -s -o /dev/null -w "req $i: %{http_code}\n" \
    https://<ingress-gw>/api/orders/TW-1001 \
    -H "client_id: ..." -H "client_secret: ..."
done
```

> O limite de 5 req/min é **proposital para a demo** (dá para estourar ao vivo). Em uso real,
> algo como 60–120 req/min.
