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

## Observações

- O volume `wso2_repository` persiste apenas artefatos de runtime em `repository/deployment/server`.
- A configuração principal fica em `wso2-config/repository/conf/deployment.toml` e é copiada pelo entrypoint oficial da imagem WSO2.
- O volume `mysql_data` só roda os scripts de inicialização na primeira criação. Se alterar nomes de bancos ou usuários depois, recrie o volume conscientemente.
- O phpMyAdmin não sobe por padrão e `PMA_ARBITRARY` fica desativado.
