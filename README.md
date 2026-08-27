# noogym-devops-configs

Configuracoes de DevOps para o WSO2 API Manager.

## WSO2 API Manager

Este compose sobe:

- WSO2 API Manager 4.7.0 com MySQL Connector/J.
- MySQL 8.0 inicializado com os schemas oficiais do WSO2 para `shared_db` e `apim_db`.
- Nginx interno `mgt-proxy`, buildado por este repo, para publicar Publisher, DevPortal, Admin e Carbon no Caddy/Coolify sem o Caddy falar diretamente com a porta TLS `9443`.
- Nginx interno `gateway-proxy`, buildado por este repo, para publicar o Gateway WSO2 no Caddy/Coolify sem o Caddy falar diretamente com a porta TLS `8243`.
- phpMyAdmin opcional, isolado no profile `tools`.

## Configuracao

Copie `.env.example` para `.env` em ambiente local, ou cadastre as mesmas variaveis no Coolify.

Antes do primeiro startup, gere um valor unico para `APIM_ENCRYPTION_KEY` com 64 caracteres hexadecimais. No PowerShell:

```powershell
$bytes = [byte[]]::new(32)
[System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
-join ($bytes | ForEach-Object { $_.ToString("x2") })
```

Troque todas as senhas `change-me-*` antes de subir.

Nas variaveis `SHARED_DB_URL` e `APIM_DB_URL`, mantenha `&amp;` entre os parametros da query string. O WSO2 gera XML interno a partir do `deployment.toml`, entao `&` cru quebra o parser.

## Executar Localmente

```bash
docker compose --env-file .env up -d --build
```

Para subir tambem o phpMyAdmin:

```bash
docker compose --env-file .env --profile tools up -d --build
```

## Coolify

No Coolify, configure as variaveis do `.env.example` como environment variables/secrets do servico.

As decisoes de arquitetura, diagnosticos e comandos de validacao estao documentados em `docs/adr/0001-wso2-apim-coolify-caddy-proxy.md`.

Portas internas esperadas:

- `8081`: proxy HTTP interno para Publisher, DevPortal, Admin e Carbon. Use esta porta no Coolify/Caddy para `gateway.noogym.com`.
- `8080`: proxy HTTP interno para o Gateway HTTPS do WSO2. Use esta porta no Coolify/Caddy para o host publico de consumo das APIs.
- `9443`: Publisher, DevPortal, Admin e Carbon via HTTPS, usado apenas pelos proxies internos.
- `8243`: Gateway HTTPS, usado apenas pelos proxies internos.
- `8280`: Gateway HTTP.
- `9099`: WebSocket.
- `80`: phpMyAdmin, apenas se o profile `tools` for ativado.

Use dominios reais nas variaveis `APIM_HOSTNAME`, `APIM_MGT_BASE_URL`, `APIM_GATEWAY_HTTP_URL`, `APIM_GATEWAY_HTTPS_URL`, `APIM_GATEWAY_WS_URL` e `APIM_GATEWAY_WSS_URL`.

### Coolify/Caddy com backend HTTPS

As portas `9443` e `8243` do WSO2 aceitam somente HTTPS internamente. Se o dominio retornar `Bad Request: This combination of host and port requires TLS`, algum proxy esta tentando falar HTTP com uma porta TLS do WSO2.

Para evitar que a geracao automatica do Coolify/Caddy aponte HTTP diretamente para `9443`, o compose publica os consoles pelo servico `mgt-proxy` na porta HTTP `8081`. Esse proxy interno recebe HTTP do Caddy e chama o WSO2 em HTTPS na porta `9443`, com verificacao TLS interna desativada para aceitar o certificado autoassinado do WSO2.

Para `gateway.noogym.com/publisher`, defina:

```env
CADDY_MGT_HOST=gateway.noogym.com
CADDY_INGRESS_NETWORK=coolify
APIM_HOSTNAME=gateway.noogym.com
APIM_MGT_BASE_URL=https://gateway.noogym.com
```

As labels equivalentes no servico `mgt-proxy` sao:

```ini
caddy=gateway.noogym.com
caddy.reverse_proxy={{upstreams 8081}}
caddy_ingress_network=coolify
```

O `mgt-proxy` tambem redireciona `/` para `/publisher`, evitando que a raiz do dominio caia no WSO2 como uma URL invalida. O healthcheck usa `/healthz`, respondido localmente pelo Nginx com `204`.

Para evitar o mesmo problema no Gateway HTTPS do WSO2 (`8243`), o compose expoe o servico `gateway-proxy` na porta HTTP `8080`. Esse proxy interno recebe HTTP do Caddy e chama o WSO2 em HTTPS na porta `8243`, com verificacao TLS interna desativada para aceitar o certificado autoassinado do WSO2. A configuracao dos proxies Nginx e copiada para dentro das imagens em build time, entao o Coolify nao precisa montar arquivo de configuracao do host.

O healthcheck do `gateway-proxy` usa `/healthz`, respondido localmente pelo Nginx com `204`. Isso evita chamadas periodicas para `/` no Gateway WSO2, que aparecem no log como `Message dispatched to the main sequence. Invalid URL.`.

Para o host publico de consumo das APIs, defina:

```env
CADDY_GATEWAY_HOST=api-gateway.noogym.com
APIM_GATEWAY_HTTPS_URL=https://api-gateway.noogym.com
```

No Coolify, o dominio de management (`gateway.noogym.com`) deve apontar para o servico `mgt-proxy` na porta `8081`, ou ficar controlado pelos labels Caddy desse servico. O dominio do Gateway de APIs deve apontar para o servico `gateway-proxy` na porta `8080`, ou ficar controlado pelos labels Caddy desse servico.

No Coolify, exponha apenas a porta que o dominio deve usar:

- `8081` no servico `mgt-proxy` para Publisher, DevPortal, Admin Console e Carbon.
- `8080` no servico `gateway-proxy` para o Gateway de consumo das APIs.

Em `Custom Docker Labels`, a configuracao equivalente para o gateway de APIs e:

```ini
caddy=api-gateway.noogym.com
caddy.reverse_proxy={{upstreams 8080}}
caddy_ingress_network=coolify
```

Se usar somente um dominio para tudo, configure regras de path no Caddy manualmente para separar os consoles (`9443`) do Gateway de APIs (`8243`/`8080`). Nao deixe dois servicos com o mesmo valor de `caddy`, porque eles disputarao o mesmo host.

Com Cloudflare em proxy ativo, mantenha o modo SSL/TLS como `Full` ou `Full (Strict)`. Evite `Flexible`, porque ele pode forcar HTTP entre Cloudflare e Caddy.

## Observacoes

- O volume `wso2_repository` persiste apenas artefatos de runtime em `repository/deployment/server`.
- A configuracao principal fica em `wso2-config/repository/conf/deployment.toml` e e embutida na imagem `noogym-wso2am:4.7.0-mysql`. O entrypoint oficial da imagem WSO2 copia essa configuracao para o produto antes do startup.
- O volume `mysql_data` so roda os scripts de inicializacao na primeira criacao. Se alterar nomes de bancos ou usuarios depois, recrie o volume conscientemente.
- O phpMyAdmin nao sobe por padrao e `PMA_ARBITRARY` fica desativado.
