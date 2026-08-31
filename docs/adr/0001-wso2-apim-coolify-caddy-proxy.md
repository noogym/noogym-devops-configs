# ADR 0001: Publicar WSO2 API Manager atras de Coolify/Caddy usando proxies HTTP internos

Status: Accepted

Date: 2026-08-27

## Context

Este repositorio publica o WSO2 API Manager 4.7.0 em Docker Compose, com MySQL 8.0 e Coolify/Caddy como proxy publico.

O WSO2 expoe duas portas HTTPS internas importantes:

- `9443`: consoles de management, incluindo Publisher, DevPortal, Admin Console, Carbon e OAuth2.
- `8243`: Gateway HTTPS para consumo de APIs.

Essas portas esperam TLS. Quando o Coolify/Caddy gera um upstream automatico como:

```caddy
reverse_proxy 172.21.0.4:9443
```

o Caddy fala HTTP com a porta `9443`. O WSO2 rejeita a requisicao com:

```text
Bad Request
This combination of host and port requires TLS.
```

O mesmo tipo de problema pode acontecer com a porta `8243`.

Tambem vimos que, quando o healthcheck ou o browser acessam `/` no Gateway WSO2, o WSO2 registra:

```text
Message dispatched to the main sequence. Invalid URL., RESOURCE = /
```

Isso nao significa que o WSO2 caiu. Significa que `/` nao e uma API publicada nem uma aplicacao web valida naquele listener.

## Problem

O Coolify facilita a exposicao de dominios, mas a geracao automatica de Caddy para portas internas nao e adequada quando a porta do backend exige HTTPS e usa certificado autoassinado, como o WSO2 faz por padrao com `wso2carbon.jks`.

Tentamos resolver diretamente no Caddy com labels equivalentes a:

```ini
caddy=gateway.noogym.com
caddy.reverse_proxy=https://{{upstreams 9443}}
caddy.reverse_proxy.transport=http
caddy.reverse_proxy.transport.tls_insecure_skip_verify=
caddy.reverse_proxy.transport.tls_server_name=gateway.noogym.com
```

Essa abordagem e valida em Caddy puro, mas na pratica ficou fragil no Coolify porque:

- a UI do Coolify ainda podia gerar uma rota automatica para `api-manager:9443` sem `https://`;
- o `Caddyfile.autosave` mostrou que a config efetiva ainda era `reverse_proxy 172.21.0.4:9443`;
- trocar somente a porta para `8081` no servico errado gerou `reverse_proxy 172.21.0.4:8081`, onde `172.21.0.4` era o `api-manager`, nao o proxy correto;
- o uso de `handle_path /*` gerado pelo Coolify pode remover prefixos de path em cenarios onde o backend precisa receber o path completo.

O diagnostico real sempre deve olhar a configuracao efetiva do Caddy, nao apenas o Compose ou as labels esperadas.

## Decision

Usamos proxies Nginx internos em HTTP para isolar o Coolify/Caddy dos detalhes de TLS do WSO2.

Arquitetura final:

```text
Browser/Cloudflare
  -> HTTPS Coolify/Caddy
  -> HTTP mgt-proxy:8081
  -> HTTPS api-manager:9443
```

e:

```text
API clients/Cloudflare
  -> HTTPS Coolify/Caddy
  -> HTTP gateway-proxy:8080
  -> HTTPS api-manager:8243
```

Com isso, o Caddy so fala HTTP com portas HTTP reais (`8081` e `8080`). Quem fala HTTPS com o WSO2 sao os proxies internos.

## Services

### api-manager

Roda o WSO2 API Manager.

Portas internas expostas:

- `9443`: management HTTPS.
- `8243`: gateway HTTPS.
- `8280`: gateway HTTP.
- `9099`: WebSocket.

O servico `api-manager` nao deve receber dominio publico diretamente no Coolify.

Nao cadastrar:

```text
gateway.noogym.com -> api-manager:9443
gateway.noogym.com -> api-manager:8081
```

Essas combinacoes quebram por protocolo errado ou por porta inexistente.

### mgt-proxy

Proxy Nginx interno para Publisher, DevPortal, Admin, Carbon e OAuth2.

Fluxo:

```text
Coolify/Caddy -> http://mgt-proxy:8081 -> https://api-manager:9443
```

Responsabilidades:

- escutar HTTP em `8081`;
- fazer proxy para `https://api-manager:9443`;
- desativar verificacao TLS interna porque o WSO2 usa certificado autoassinado;
- repassar `Host`, `X-Forwarded-Host`, `X-Forwarded-Proto=https` e `X-Forwarded-Port=443`;
- redirecionar `/` para `/publisher`;
- responder `/healthz` localmente com `204`.

Dominio esperado no Coolify:

```text
gateway.noogym.com -> mgt-proxy:8081
```

### gateway-proxy

Proxy Nginx interno para o Gateway HTTPS do WSO2.

Fluxo:

```text
Coolify/Caddy -> http://gateway-proxy:8080 -> https://api-manager:8243
```

Responsabilidades:

- escutar HTTP em `8080`;
- fazer proxy para `https://api-manager:8243`;
- desativar verificacao TLS interna porque o WSO2 usa certificado autoassinado;
- repassar headers de proxy;
- responder `/healthz` localmente com `204`.

Dominio esperado no Coolify:

```text
api-gateway.noogym.com -> gateway-proxy:8080
```

## WSO2 configuration

O WSO2 precisa conhecer o endereco publico correto. No Coolify, as variaveis devem ser:

```env
APIM_HOSTNAME=gateway.noogym.com
APIM_MGT_BASE_URL=https://gateway.noogym.com
APIM_DEVPORTAL_URL=https://gateway.noogym.com/devportal
APIM_GATEWAY_HTTPS_URL=https://api-gateway.noogym.com
```

As demais URLs devem ser coerentes com os dominios reais:

```env
APIM_GATEWAY_HTTP_URL=http://api-gateway.noogym.com
APIM_GATEWAY_WS_URL=ws://api-gateway.noogym.com
APIM_GATEWAY_WSS_URL=wss://api-gateway.noogym.com
```

O arquivo fonte fica em:

```text
wso2-config/repository/conf/deployment.toml
```

Ele usa env vars:

```toml
[server]
hostname = "$env{APIM_HOSTNAME}"
base_path = "$env{APIM_MGT_BASE_URL}"

[transport.https.properties]
proxyPort = 443
proxyHost = "$env{APIM_HOSTNAME}"

[apim.devportal]
url = "$env{APIM_DEVPORTAL_URL}"
```

O `proxyPort = 443` e necessario para que o WSO2 gere redirects e callbacks OAuth usando a porta publica do proxy, e nao a porta interna `9443`. Sem isso, o Publisher pode sair de `localhost`, mas ainda redirecionar para URLs como:

```text
https://gateway.noogym.com:9443/authenticationendpoint/login.do
```

A documentacao oficial do WSO2 para reverse proxy/load balancer recomenda configurar o proxy port no `deployment.toml` com `[transport.https.properties] proxyPort = 443` quando o acesso publico passa pelo proxy em `443`.

A documentacao oficial de mudanca de hostname tambem recomenda configurar `[apim.devportal] url`, que e a URL usada para acessar o Developer Portal a partir do Publisher. O default do produto aponta para `https://localhost:9443/devportal`; por isso definimos `APIM_DEVPORTAL_URL` explicitamente.

As JDBC URLs tambem ficam neste arquivo e sao montadas a partir dos nomes dos bancos:

```toml
[database.shared_db]
url = "jdbc:mysql://mysql-db:3306/$env{SHARED_DB_NAME}?useSSL=false&amp;allowPublicKeyRetrieval=true&amp;serverTimezone=UTC"

[database.apim_db]
url = "jdbc:mysql://mysql-db:3306/$env{APIM_DB_NAME}?useSSL=false&amp;allowPublicKeyRetrieval=true&amp;serverTimezone=UTC"
```

Nao usar `SHARED_DB_URL` nem `APIM_DB_URL` como variaveis do Coolify. Se uma JDBC URL for definida com `&` cru, o WSO2 gera um `master-datasources.xml` invalido e falha antes de abrir `9443`:

```text
Unexpected character '='; expected a semi-colon after the reference for entity 'allowPublicKeyRetrieval'
Name [jdbc/SHARED_DB] is not bound in this Context
```

O `wso2-config/` e embutido na imagem `noogym-wso2am:4.7.0-mysql` pelo Dockerfile. Isso foi decidido porque, no Coolify, o bind mount para `/home/wso2carbon/wso2-config-volume` nao estava chegando como esperado. O resultado era o WSO2 subir com o `deployment.toml` default:

```toml
hostname = "localhost"
base_path = "${carbon.protocol}://${carbon.host}:${carbon.management.port}"
```

Quando isso acontece, o Publisher carrega e depois redireciona o login OAuth para:

```text
https://localhost:9443/oauth2/authorize
```

Por isso o build do `api-manager` usa o contexto raiz do repo e copia `wso2-config/` para:

```text
/home/wso2carbon/wso2-config-volume/
```

O entrypoint oficial da imagem WSO2 copia esse conteudo para o produto antes do startup.

## Diagnostics

### Verificar a config efetiva do Caddy

Dentro do container `coolify-proxy`:

```sh
cat /config/caddy/Caddyfile.autosave
```

Correto para management:

```caddy
reverse_proxy 172.x.x.x:8081
```

O IP deve ser do container `mgt-proxy`.

Errado:

```caddy
reverse_proxy 172.x.x.x:9443
```

Tambem errado:

```caddy
reverse_proxy <ip-do-api-manager>:8081
```

Nesse segundo caso, o dominio foi alterado para a porta certa, mas continuou cadastrado no servico errado.

### Mapear IPs dos containers

Na VPS:

```bash
docker ps --format "table {{.ID}}\t{{.Names}}\t{{.Ports}}\t{{.Networks}}"
docker inspect <mgt-proxy-container> --format '{{range $name,$net := .NetworkSettings.Networks}}{{$name}} {{$net.IPAddress}}{{"\n"}}{{end}}'
docker inspect <api-manager-container> --format '{{range $name,$net := .NetworkSettings.Networks}}{{$name}} {{$net.IPAddress}}{{"\n"}}{{end}}'
```

Se o Caddy aponta para o IP do `api-manager` com porta `8081`, o resultado sera `502` e `connection refused`, porque o `api-manager` nao escuta `8081`.

### Testar o mgt-proxy a partir do Caddy

Dentro do container `coolify-proxy`:

```sh
curl -v http://<ip-do-mgt-proxy>:8081/healthz
```

Esperado:

```text
HTTP/1.1 204 No Content
```

Testar o Publisher com Host real:

```sh
curl -v -H "Host: gateway.noogym.com" http://<ip-do-mgt-proxy>:8081/publisher
```

Esperado:

```text
HTTP/1.1 302
Location: https://gateway.noogym.com/publisher/
```

Se o Location apontar para IP interno, o teste foi feito sem `Host`.

### Verificar se o WSO2 recebeu o deployment.toml correto

Dentro do container `api-manager`:

```bash
docker exec -it <api-manager-container> sh -lc 'head -n 6 /home/wso2carbon/wso2am-4.7.0/repository/conf/deployment.toml'
```

Correto:

```toml
[server]
hostname = "$env{APIM_HOSTNAME}"
base_path = "$env{APIM_MGT_BASE_URL}"
```

Errado:

```toml
[server]
hostname = "localhost"
base_path = "${carbon.protocol}://${carbon.host}:${carbon.management.port}"
```

### Verificar settings do Publisher

Da maquina local ou VPS:

```bash
curl -ks https://gateway.noogym.com/publisher/site/public/conf/settings.json | grep -iE "localhost|gateway"
```

Correto: nao deve aparecer `localhost`.

Se aparecer:

```json
"host": "localhost"
```

o WSO2 ainda esta usando a config default ou uma config antiga.

### Erro invalid_callback depois de corrigir hostname e proxyPort

Depois que `localhost` e `:9443` desaparecem das URLs publicas, ainda pode aparecer:

```text
authenticationendpoint/oauth2_error.do?oauthErrorCode=invalid_callback
Registered callback does not match with the provided url.
```

Isso significa que o proxy e o hostname ja estao corretos, mas a aplicacao OAuth interna do WSO2 foi registrada anteriormente com outro callback.

Exemplos de callbacks antigos:

```text
https://localhost:9443/publisher/services/auth/callback/login
https://gateway.noogym.com:9443/publisher/services/auth/callback/login
```

Callback correto:

```text
https://gateway.noogym.com/publisher/services/auth/callback/login
```

Em ambiente novo, a solucao mais limpa e remover os containers do projeto, apagar os volumes `mysql-data` e `wso2-repository`, e fazer redeploy com rebuild. Assim o WSO2 recria as aplicacoes OAuth internas ja com `APIM_HOSTNAME`, `APIM_MGT_BASE_URL` e `proxyPort` corretos.

Em ambiente com dados importantes, nao apagar volumes. Corrigir com cuidado a aplicacao OAuth persistida no banco, procurando callbacks com `localhost:9443` ou `gateway.noogym.com:9443`.

### Link do DevPortal volta para localhost

Se um clique no DevPortal levar para:

```text
https://localhost:9443/devportal/apis/<api-id>/overview
```

verificar se `[apim.devportal] url` esta configurado e se a variavel `APIM_DEVPORTAL_URL` no Coolify aponta para:

```env
APIM_DEVPORTAL_URL=https://gateway.noogym.com/devportal
```

Tambem verificar:

```bash
curl -ks https://gateway.noogym.com/devportal/site/public/conf/settings.json | grep -iE "localhost|9443|gateway"
```

Se ainda houver `localhost` depois do rebuild, tratar como estado antigo persistido no MySQL/artefatos criados antes da correcao.

## Operational rules

1. O dominio `gateway.noogym.com` deve ficar no servico `mgt-proxy`, porta `8081`.
2. O dominio de consumo de APIs deve ficar no servico `gateway-proxy`, porta `8080`.
3. Nao publicar `api-manager:9443` diretamente pelo Coolify automatico.
4. Nao trocar apenas a porta do dominio dentro do servico `api-manager`; isso gera `api-manager:8081`, que nao existe.
5. Sempre verificar `/config/caddy/Caddyfile.autosave` depois de mudar dominios no Coolify.
6. Sempre fazer rebuild do `api-manager` quando mudar `wso2-config/`.
7. Se o ambiente foi inicializado com `localhost` ou `:9443` publico, dados persistidos no MySQL podem manter callbacks OAuth antigos e causar `invalid_callback`. Em ambiente novo, recriar os volumes e mais simples. Em ambiente com dados, corrigir as entradas persistidas no banco com cuidado.
8. `mgt-proxy` e `gateway-proxy` dependem apenas de `service_started` do `api-manager`. Eles nao devem esperar `service_healthy`, porque seus healthchecks sao locais e o WSO2 pode demorar muitos minutos para ficar pronto no primeiro startup.
9. O healthcheck do `api-manager` e deliberadamente tolerante (`start_period` longo), para evitar que o Coolify marque o deploy como falho enquanto o WSO2 ainda esta inicializando.
10. Nao configurar JDBC URLs completas em variaveis do Coolify. O `deployment.toml` deve montar essas URLs internamente com `&amp;`, porque o WSO2 transforma essa configuracao em XML.
11. Manter `[transport.https.properties] proxyPort = 443`, para impedir que `9443` vaze para redirects e callbacks publicos.
12. Definir `APIM_DEVPORTAL_URL` e `[apim.devportal] url`, para impedir que links entre Publisher e DevPortal usem o default `https://localhost:9443/devportal`.

## Consequences

Beneficios:

- evita depender de transporte HTTPS customizado no Caddy gerado pelo Coolify;
- elimina o erro `This combination of host and port requires TLS`;
- separa claramente management (`8081`) de gateway de APIs (`8080`);
- remove ruido de healthcheck no log do WSO2;
- torna o diagnostico mais objetivo.

Custos:

- adiciona dois containers Nginx pequenos;
- desativa verificacao TLS apenas no trafego interno Nginx -> WSO2;
- exige rebuild da imagem `api-manager` quando a configuracao WSO2 mudar;
- exige cuidado para nao cadastrar dominios no servico errado na UI do Coolify.

## Alternatives considered

### Caddy falar HTTPS direto com WSO2

Funciona em Caddyfile manual:

```caddy
gateway.noogym.com {
    reverse_proxy https://api-manager:9443 {
        transport http {
            tls_insecure_skip_verify
            tls_server_name gateway.noogym.com
        }
    }
}
```

Nao foi escolhido porque a UI do Coolify e o `caddy-docker-proxy` geraram configuracao efetiva diferente em alguns momentos. O `Caddyfile.autosave` mostrou upstream HTTP direto para `9443`.

### Desativar portas HTTP do WSO2

Nao resolve este problema. O erro aconteceu porque o proxy falava HTTP com uma porta HTTPS (`9443`), nao porque o WSO2 aceitava HTTP em outra porta.

Desativar portas HTTP pode ser uma melhoria futura de hardening, mas nao e a correcao para este incidente.
