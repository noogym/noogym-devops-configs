# noogym-devops-configs

Configurações de DevOps para o WSO2 API Manager.

## WSO2 API Manager

Este compose sobe:

- WSO2 API Manager 4.7.0 com MySQL Connector/J.
- MySQL 8.0 inicializado com os schemas oficiais do WSO2 para `shared_db` e `apim_db`.
- Nginx interno `gateway-proxy`, buildado por este repo, para publicar o Gateway WSO2 no Caddy/Coolify sem erro de TLS e com healthcheck próprio.
- phpMyAdmin opcional, isolado no profile `tools`.

## Configuração

Copie `.env.example` para `.env` em ambiente local, ou cadastre as mesmas variáveis no Coolify.

Antes do primeiro startup, gere um valor único para `APIM_ENCRYPTION_KEY` com 64 caracteres hexadecimais. No PowerShell:

```powershell
$bytes = [byte[]]::new(32)
[System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
-join ($bytes | ForEach-Object { $_.ToString("x2") })
```

Troque todas as senhas `change-me-*` antes de subir.

Nas variáveis `SHARED_DB_URL` e `APIM_DB_URL`, mantenha `&amp;` entre os parâmetros da query string. O WSO2 gera XML interno a partir do `deployment.toml`, então `&` cru quebra o parser.

## Executar Localmente

```bash
docker compose --env-file .env up -d --build
```

Para subir também o phpMyAdmin:

```bash
docker compose --env-file .env --profile tools up -d --build
```

## Coolify

No Coolify, configure as variáveis do `.env.example` como environment variables/secrets do serviço.

Portas internas esperadas:

- `9443`: Publisher, DevPortal, Admin e Carbon via HTTPS. Use esta porta no Coolify/Caddy para `gateway.noogym.com`.
- `8080`: proxy HTTP interno para o Gateway HTTPS do WSO2. Use esta porta no Coolify para o host público de consumo das APIs.
- `8243`: Gateway HTTPS.
- `8280`: Gateway HTTP.
- `9099`: WebSocket.
- `80`: phpMyAdmin, apenas se o profile `tools` for ativado.

Use domínios reais nas variáveis `APIM_HOSTNAME`, `APIM_MGT_BASE_URL`, `APIM_GATEWAY_HTTP_URL`, `APIM_GATEWAY_HTTPS_URL`, `APIM_GATEWAY_WS_URL` e `APIM_GATEWAY_WSS_URL`.

### Coolify/Caddy com backend HTTPS

As portas `9443` e `8243` do WSO2 aceitam somente HTTPS internamente. Se o domínio retornar `Bad Request: This combination of host and port requires TLS`, o Caddy está tentando falar HTTP com uma porta TLS do WSO2.

Para Publisher, DevPortal, Admin Console e Carbon, o compose publica o serviço `api-manager` diretamente no Caddy com upstream HTTPS para a porta `9443`. As labels configuram o transporte HTTP do Caddy com `tls_insecure_skip_verify` para aceitar o certificado autoassinado padrão do WSO2 e `tls_server_name` para enviar o SNI esperado.

Para `gateway.noogym.com/publisher`, defina:

```env
CADDY_MGT_HOST=gateway.noogym.com
CADDY_MGT_TLS_SERVER_NAME=gateway.noogym.com
CADDY_INGRESS_NETWORK=coolify
APIM_MGT_BASE_URL=https://gateway.noogym.com
```

As labels equivalentes no serviço `api-manager` são:

```ini
caddy=gateway.noogym.com
caddy.reverse_proxy=https://{{upstreams 9443}}
caddy.reverse_proxy.transport=http
caddy.reverse_proxy.transport.tls_insecure_skip_verify=
caddy.reverse_proxy.transport.tls_server_name=gateway.noogym.com
caddy_ingress_network=coolify
```

Para evitar o mesmo problema no Gateway HTTPS do WSO2 (`8243`), o compose também expõe o serviço `gateway-proxy` na porta HTTP `8080`. Esse proxy interno recebe HTTP do Caddy e chama o WSO2 em HTTPS na porta `8243`, com verificação TLS interna desativada para aceitar o certificado autoassinado do WSO2. A configuração do Nginx é copiada para dentro da imagem em build time, então o Coolify não precisa montar arquivo de configuração do host.

O healthcheck do `gateway-proxy` usa `/healthz`, respondido localmente pelo Nginx com `204`. Isso evita chamadas periódicas para `/` no Gateway WSO2, que aparecem no log como `Message dispatched to the main sequence. Invalid URL.`.

Para o host público de consumo das APIs, defina:

```env
CADDY_GATEWAY_HOST=api-gateway.noogym.com
APIM_GATEWAY_HTTPS_URL=https://api-gateway.noogym.com
```

No Coolify, o domínio de management (`gateway.noogym.com`) deve ficar controlado pelas labels do serviço `api-manager` na porta `9443`. O domínio do Gateway de APIs deve apontar para o serviço `gateway-proxy` na porta `8080`, ou ficar controlado pelos labels Caddy desse serviço.

No Coolify, exponha apenas a porta que o domínio deve usar:

- `9443` no serviço `api-manager` para Publisher, DevPortal, Admin Console e Carbon.
- `8080` no serviço `gateway-proxy` para o Gateway de consumo das APIs.

Em `Custom Docker Labels`, a configuração equivalente para o gateway agora é:

```ini
caddy=api-gateway.noogym.com
caddy.reverse_proxy={{upstreams 8080}}
caddy_ingress_network=coolify
```

Se usar somente um domínio para tudo, configure regras de path no Caddy manualmente para separar os consoles (`9443`) do Gateway de APIs (`8243`/`8080`). Não deixe dois serviços com o mesmo valor de `caddy`, porque eles disputarão o mesmo host.

Com Cloudflare em proxy ativo, mantenha o modo SSL/TLS como `Full` ou `Full (Strict)`. Evite `Flexible`, porque ele pode forçar HTTP entre Cloudflare e Caddy.

## Observações

- O volume `wso2_repository` persiste apenas artefatos de runtime em `repository/deployment/server`.
- A configuração principal fica em `wso2-config/repository/conf/deployment.toml` e é copiada pelo entrypoint oficial da imagem WSO2.
- O volume `mysql_data` só roda os scripts de inicialização na primeira criação. Se alterar nomes de bancos ou usuários depois, recrie o volume conscientemente.
- O phpMyAdmin não sobe por padrão e `PMA_ARBITRARY` fica desativado.
