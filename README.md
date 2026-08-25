# noogym-devops-configs

Configurações de DevOps para o WSO2 API Manager.

## WSO2 API Manager

Este compose sobe:

- WSO2 API Manager 4.7.0 com MySQL Connector/J.
- MySQL 8.0 inicializado com os schemas oficiais do WSO2 para `shared_db` e `apim_db`.
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

- `9443`: Publisher, DevPortal, Admin e Carbon via HTTPS.
- `8243`: Gateway HTTPS.
- `8280`: Gateway HTTP.
- `9099`: WebSocket.
- `80`: phpMyAdmin, apenas se o profile `tools` for ativado.

Use domínios reais nas variáveis `APIM_HOSTNAME`, `APIM_MGT_BASE_URL`, `APIM_GATEWAY_HTTP_URL`, `APIM_GATEWAY_HTTPS_URL`, `APIM_GATEWAY_WS_URL` e `APIM_GATEWAY_WSS_URL`.

### Coolify/Caddy com backend HTTPS

As portas `9443` e `8243` do WSO2 aceitam somente HTTPS internamente. Se o domínio retornar `Bad Request: This combination of host and port requires TLS`, o Caddy está tentando falar HTTP com uma porta TLS do WSO2.

O `docker-compose.yaml` já cria labels Caddy para o gateway usando `CADDY_GATEWAY_HOST` e apontando para a porta interna `8243` com upstream HTTPS. Como o WSO2 usa certificado interno autoassinado, o label `caddy.reverse_proxy.transport.tls_insecure_skip_verify` também é aplicado. Para `gateway.noogym.com`, defina:

```env
CADDY_GATEWAY_HOST=gateway.noogym.com
CADDY_INGRESS_NETWORK=coolify
APIM_GATEWAY_HTTPS_URL=https://gateway.noogym.com
```

Se o Coolify tiver criado outra configuração automática para o mesmo domínio, remova esse domínio/configuração automática ou garanta que os labels `caddy.*` deste compose sejam os que ficam ativos. Configuração automática apontando HTTP para `8243` causa o erro `This combination of host and port requires TLS`.

No Coolify, exponha apenas a porta que o domínio deve usar:

- `9443` para Publisher, DevPortal, Admin Console e Carbon.
- `8243` para o Gateway HTTPS de consumo das APIs.

Em `Custom Docker Labels`, a configuração equivalente para o gateway é:

```ini
caddy=gateway.noogym.com
caddy.reverse_proxy={{upstreams https 8243}}
caddy.reverse_proxy.transport=http
caddy.reverse_proxy.transport.tls_insecure_skip_verify=
caddy_ingress_network=coolify
```

Use `9443` no upstream quando o domínio for para os consoles de administração. Para `gateway.noogym.com`, normalmente use `8243`.

Com Cloudflare em proxy ativo, mantenha o modo SSL/TLS como `Full` ou `Full (Strict)`. Evite `Flexible`, porque ele pode forçar HTTP entre Cloudflare e Caddy.

## Observações

- O volume `wso2_repository` persiste apenas artefatos de runtime em `repository/deployment/server`.
- A configuração principal fica em `wso2-config/repository/conf/deployment.toml` e é copiada pelo entrypoint oficial da imagem WSO2.
- O volume `mysql_data` só roda os scripts de inicialização na primeira criação. Se alterar nomes de bancos ou usuários depois, recrie o volume conscientemente.
- O phpMyAdmin não sobe por padrão e `PMA_ARBITRARY` fica desativado.
