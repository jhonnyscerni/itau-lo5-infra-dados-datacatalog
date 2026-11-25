# Etapa 4 — Roteiro de teste da publicação no SNS (tblo5046_limi_opel_flxl)

Valida o fluxo ponta a ponta em **dev**:
SNS `lo5-data-ingestion-topic` → Firehose `delivery_stream_limites_tblo5046_limi_opel_flxl` → S3 → Glue (partições via add-partition) → Athena.

## 0. Pré-requisitos

- [ ] Parte 1 (datacatalog) aplicada em dev — tabela + permissão Lake Formation
- [ ] Parte 2 (connector-events) aplicada em dev — chave `connector_tblo5046_limi_opel_flxl`
- [ ] Parte 3 (add-partition) aplicada em dev — tabela na lista `tables`
- [ ] Perfil AWS da conta de dev com `sns:Publish` no tópico, `s3:ListBucket`, `glue:GetPartitions` e acesso ao Athena

| Item | dev |
|---|---|
| Conta | `435908583578` |
| Região | `sa-east-1` |
| Tópico | `arn:aws:sns:sa-east-1:435908583578:lo5-data-ingestion-topic` |
| Bucket/prefixo | `s3://itau-corp-sor-sa-east-1-435908583578/tblo5046_limi_opel_flxl/` |
| Database | `db_source_fraudeepld_limitesoperacionais_sor_01` |
| Firehose | `delivery_stream_limites_tblo5046_limi_opel_flxl` |
| Log group | `Phoenix-events/delivery_stream_limites_tblo5046_limi_opel_flxl` |
| Step Function | `lo5-datamesh-addpartition-sfn` (cron de hora em hora) |

> Confirme na console que o tópico está mesmo na conta de dev; ajuste o ARN se não estiver.

## 0.1 Validação só com a conta produtora (sem acesso à conta de controle)

Quem tem acesso apenas à conta **`435908583578`** consegue validar o fluxo inteiro — só o catálogo (Glue/Athena) fica na conta de controle `773683090477`.

| # | O que confere | Onde (console da conta 3578) | Esperado |
|---|---|---|---|
| 1 | Parte 1 aplicada (tabela existe) | **CloudTrail → Event history** → Event name = `CreateTable` | Evento sem `errorCode`, com `catalogId: 773683090477` e `tableInput.name: tblo5046_limi_opel_flxl` |
| 1b | Permissão Lake Formation | **CloudTrail → Event history** → Event name = `GrantPermissions` | Evento sem `errorCode` |
| 2 | Parte 2: assinatura SNS → Firehose | **SNS → Topics → `lo5-data-ingestion-topic` → Subscriptions** | Assinatura `firehose` → `delivery_stream_limites_tblo5046_limi_opel_flxl`, filtro `event_type` |
| 3 | Publicação | **SNS → Publish message** (seção 2.1) | Banner verde com Message ID |
| 4 | Firehose recebeu e entregou | **Amazon Data Firehose → `delivery_stream_limites_tblo5046_limi_opel_flxl` → Monitoring** | *Incoming records* e *Delivery to S3 success* > 0 |
| 5 | Arquivo no S3 | **S3 → `itau-corp-sor-sa-east-1-435908583578` → `tblo5046_limi_opel_flxl/`** | `.parquet` novo ~60s depois |
| 6 | Parte 3: partição criada | **Step Functions → `lo5-datamesh-addpartition-sfn` → Executions** | Execução após a hora cheia = *Succeeded* |
| 7 | Nada na DLQ | **SQS → DLQ da fila `lo5-datamesh-addpartiton-phoenix`** | 0 mensagens |

> **O passo 5 é a prova principal:** o Firehose converte JSON → Parquet **lendo o schema da tabela no Glue da conta de controle**. Se o `.parquet` aparecer no prefixo normal, a tabela existe e a permissão do Lake Formation funciona. Se a tabela/permissão estivesse errada, o registro iria para um prefixo de erro (`errors/` / `format-conversion-failed/`) e o alarme `DataFormatConversionFailed` dispararia.

**Fica de fora sem a conta de controle:** ver tabela/partições no Glue e consultar no Athena. Para isso, pedir ao time de plataforma Data Mesh `DESCRIBE` (e `SELECT`) no Lake Formation da conta `773683090477` para a **sua role** (nome visível no canto superior direito da console, em `role/<NOME>/...`), ou pedir que alguém de lá rode o `SHOW PARTITIONS`.

> **Por que a conta 7736…?** O Data Mesh separa dados e catálogo: o S3/Firehose/SNS/SQS/Step Function ficam na conta produtora (`435908583578` em dev) e a definição da tabela + permissões ficam na conta de controle (`773683090477` em dev, `827556317157` em hom, `973136190634` em prod). Por isso a tabela não aparece no Glue da conta 3578 — só via resource link e com permissão no Lake Formation.

## 1. Conferir a assinatura do SNS

```bash
aws sns list-subscriptions-by-topic --region sa-east-1 \
  --topic-arn arn:aws:sns:sa-east-1:435908583578:lo5-data-ingestion-topic \
  --query "Subscriptions[?Protocol=='firehose'].[SubscriptionArn,Endpoint]" --output table
```

**Esperado:** uma linha com o Endpoint terminando em `deliverystream/delivery_stream_limites_tblo5046_limi_opel_flxl`.

Conferir o filtro (troque `<SUBSCRIPTION_ARN>`):

```bash
aws sns get-subscription-attributes --region sa-east-1 \
  --subscription-arn <SUBSCRIPTION_ARN> \
  --query "Attributes.[FilterPolicy,FilterPolicyScope]"
```

**Esperado:** `{"event_type": ["tblo5046_limi_opel_flxl"]}` e `MessageAttributes`.

## 2. Publicar a mensagem de teste

```bash
aws sns publish --region sa-east-1 \
  --topic-arn arn:aws:sns:sa-east-1:435908583578:lo5-data-ingestion-topic \
  --message '{"cod_idef_pess":"TESTE-0001","num_unic_cont":"TESTE-0001","nom_situ_limi_flxl":"EM_ANDAMENTO","dat_hor_incu_rgto":"2026-11-25T10:00:00","dat_hor_expu":"2026-12-25T10:00:00","vlr_sltd":100.50,"des_moti":"teste etapa 4","des_ctto":"teste etapa 4","event_timestamp":"2026-11-25T10:00:00Z"}' \
  --message-attributes '{"event_type":{"DataType":"String","StringValue":"tblo5046_limi_opel_flxl"}}'
```

**Esperado:** retorno com `MessageId`.

Regras do payload:
- Chaves = **nomes das colunas do Glue** (campo com nome diferente vira nulo no Parquet).
- `vlr_sltd` como **número** (`decimal(10,2)`), não string.
- `event_timestamp` presente — é o campo de partição do Firehose.
- `event_type` **idêntico** a `tblo5046_limi_opel_flxl` (qualquer diferença = mensagem descartada sem erro).

### 2.1 Alternativa: publicar manualmente pela console da AWS

Console na conta de **dev**, região **São Paulo (sa-east-1)**:

1. **SNS → Topics → `lo5-data-ingestion-topic` → Publish message**.
2. **Message details:** `Subject` e `Time to Live (TTL)` em branco.
3. **Message body:**
   - **Message structure:** `Identical payload for all delivery protocols`
   - **Message body to send to the endpoint:** colar o JSON **puro** (sem envelope `"Message"`):

   ```json
   {
     "cod_idef_pess": "TESTE-0001",
     "num_unic_cont": "TESTE-0001",
     "nom_situ_limi_flxl": "EM_ANDAMENTO",
     "dat_hor_incu_rgto": "2026-11-25T10:00:00",
     "dat_hor_expu": "2026-12-25T10:00:00",
     "vlr_sltd": 100.50,
     "des_moti": "teste etapa 4",
     "des_ctto": "teste etapa 4",
     "event_timestamp": "2026-11-25T10:00:00Z"
   }
   ```

4. **Message attributes** (é aqui que o filtro da assinatura olha):

   | Type | Name | Value |
   |---|---|---|
   | `String` | `event_type` | `tblo5046_limi_opel_flxl` |

   - Type `String` (não `String.Array`), Value **sem aspas** e sem espaços sobrando.
5. **Publish message** → deve aparecer o banner verde com o **Message ID**.

> **Por que o corpo vai "puro":** a assinatura do Firehose tem `raw_message_delivery = true`, então o SNS entrega **só o corpo** ao Firehose. O envelope com `Message` / `MessageAttributes` / `TopicArn` da especificação é o formato da chamada de API, não o que se digita na console. O `event_type` **não** vai dentro do JSON — se for, o filtro não enxerga e a mensagem é descartada.
>
> Se nada chegar no S3: o tópico SNS **não tem aba Monitoring** — as métricas ficam em **CloudWatch → Métricas → Métricas clássicas → SNS → Topic Metrics** → `lo5-data-ingestion-topic` (Statistic `Sum`, Period `1 minute`, intervalo 1h). Detalhes na seção **2.2**. Olhar `NumberOfMessagesPublished` (não subiu = publicou em outro tópico/conta), `NumberOfNotificationsFilteredOut` (subiu = problema no atributo `event_type`), `NumberOfNotificationsFailed` (subiu = permissão da role da assinatura no Firehose) e `NumberOfNotificationsDelivered` (subiu = chegou no Firehose).

### 2.2 Publiquei — e agora? (onde a mensagem parou)

A mensagem percorre: **publicação → tópico SNS → filtro `event_type` → entrega ao Firehose → S3**. Conferir na ordem; cada passo responde uma pergunta.

#### 2.2.1 Métricas do tópico SNS

O tópico **não tem aba Monitoring**. Duas formas:

- **Console:** CloudWatch → **Métricas → Métricas clássicas** (era "All metrics") → **SNS → Topic Metrics** → filtrar `lo5-data-ingestion-topic` → marcar as 4 métricas → **Soma (Sum)**, período **1 minuto**, intervalo **3h**.
- **CloudShell** (ícone `>_` no topo da console, conta 3578, sa-east-1) — mais rápido:

```bash
for m in NumberOfMessagesPublished NumberOfNotificationsFilteredOut NumberOfNotificationsFailed NumberOfNotificationsDelivered; do
  echo "== $m"
  aws cloudwatch get-metric-statistics --region sa-east-1 \
    --namespace AWS/SNS --metric-name $m \
    --dimensions Name=TopicName,Value=lo5-data-ingestion-topic \
    --start-time $(date -u -d '-3 hours' +%Y-%m-%dT%H:%M:%SZ) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
    --period 300 --statistics Sum \
    --query "Datapoints[].[Timestamp,Sum]" --output text
done
```

| # | Métrica | Conta | No teste deveria ser |
|---|---|---|---|
| ① | `NumberOfMessagesPublished` | mensagens que chegaram no tópico | **≥ 1** |
| ② | `NumberOfNotificationsFilteredOut` | descartadas pelo filtro da assinatura | **0** |
| ③ | `NumberOfNotificationsDelivered` | entregues ao Firehose | **≥ 1** |
| ④ | `NumberOfNotificationsFailed` | entregas que falharam | **0** |

> O tópico recebe mensagens de outras tabelas também — olhar o **horário** da sua publicação.

| Combinação | Significa | Ação |
|---|---|---|
| ① = 0 | não chegou no tópico | publicou em outro tópico/conta/região — publicar de dentro de SNS → `lo5-data-ingestion-topic` |
| ① ≥ 1 e ② ≥ 1 | filtro descartou | corrigir Message attribute (`String` / `event_type` / `tblo5046_limi_opel_flxl`) |
| ① ≥ 1 e ④ ≥ 1 | SNS não conseguiu entregar ao Firehose | permissão da role da assinatura (`iamsr/lo5-datamesh-execution-role`: `firehose:PutRecord`/`PutRecordBatch`) |
| ① ≥ 1 e ③ ≥ 1 | **chegou no Firehose** | problema (se houver) está depois → 2.2.2 |
| ① ≥ 1 e ②③④ = 0 | nenhuma assinatura pegou | aba **Subscriptions** do tópico: assinatura `firehose` existe e está `Confirmed`? |

#### 2.2.2 Para onde o Firehose grava

```bash
aws firehose describe-delivery-stream --region sa-east-1 \
  --delivery-stream-name delivery_stream_limites_tblo5046_limi_opel_flxl \
  --query "DeliveryStreamDescription.Destinations[0].ExtendedS3DestinationDescription.[BucketARN,Prefix,ErrorOutputPrefix]" \
  --output text
```

Ou console: **Amazon Data Firehose → `delivery_stream_limites_tblo5046_limi_opel_flxl` → Configuration → Destination settings** (S3 bucket, *S3 bucket prefix*, *S3 bucket error output prefix*).

Procurar o arquivo no S3 **exatamente nesses dois caminhos** — o módulo pode usar um prefixo diferente de `tblo5046_limi_opel_flxl/`.

Métricas do Firehose (essa tela **tem** aba **Monitoring**, intervalo 3h): *Incoming records* (recebeu), *Delivery to Amazon S3 success* (gravou), falhas de *data format conversion* (conversão).

#### 2.2.3 Log do Firehose (se não achar o arquivo nos dois caminhos)

```bash
aws logs filter-log-events --region sa-east-1 \
  --log-group-name "Phoenix-events/delivery_stream_limites_tblo5046_limi_opel_flxl" \
  --start-time $(( ($(date +%s) - 10800) * 1000 )) \
  --query "events[].message" --output text | head -40
```

| Erro no log | Causa |
|---|---|
| `DataFormatConversion...` / `The schema is invalid` / Glue `AccessDenied` | Firehose não leu a tabela no Glue central — permissão Lake Formation da role da pipeline |
| `could not be parsed` / `Unable to deserialize` | JSON não bate com o schema (tipo de campo) |
| `S3.AccessDenied` / `KMS.AccessDeniedException` | role não grava no bucket / não usa a chave KMS |
| nada no log | ainda no buffer — esperar alguns minutos |

## 3. Conferir o arquivo no S3 (~60s depois — `buffer_interval`)

```bash
aws s3 ls --recursive s3://itau-corp-sor-sa-east-1-435908583578/tblo5046_limi_opel_flxl/ | tail -5
```

**Esperado:** arquivo novo em `.../ano=2026/mes=11/dia=25/...` (ou no formato de prefixo usado pela `tblo5_consentimento_personalizacao`).

> **Antes do teste o prefixo não existe — é normal.** Criar a tabela no Glue não cria nada no S3 (o Glue só guarda o metadado/`location`), e no S3 não existem pastas de verdade: o "diretório" `tblo5046_limi_opel_flxl/` só aparece quando o **primeiro arquivo** é gravado pelo Firehose. O bucket `itau-corp-sor-sa-east-1-435908583578` em si já deve existir (é o mesmo da `tblo5_consentimento_personalizacao`). Se não aparecer na lista de buckets, pode ser falta de `s3:ListAllMyBuckets` — abrir direto: `https://s3.console.aws.amazon.com/s3/buckets/itau-corp-sor-sa-east-1-435908583578?region=sa-east-1`.

**Conferir em qual caminho o arquivo caiu:**

| Caminho | Significa |
|---|---|
| prefixo **normal** (`tblo5046_limi_opel_flxl/...`), arquivo **`.parquet`** | ✅ sucesso — o Firehose leu o schema no Glue central, converteu e gravou (prova tabela + permissão da pipeline + conector + filtro) |
| prefixo de **erro** (`error` / `failed` / `format-conversion-failed` no caminho) | ❌ conversão falhou — abrir o arquivo (JSON com o motivo) ou ver o log (2.2.3) |

Anotar o **caminho completo** do arquivo: mostra o formato real das partições.

Se não aparecer em até 5 minutos → seção **2.2** e **Troubleshooting**.

## 4. Conferir as partições no Glue (após a próxima hora cheia)

O add-partition roda em `cron(0 * * * ? *)`. Depois da hora cheia:

```bash
aws glue get-partitions --region sa-east-1 \
  --catalog-id 773683090477 \
  --database-name db_source_fraudeepld_limitesoperacionais_sor_01 \
  --table-name tblo5046_limi_opel_flxl \
  --query "Partitions[].Values" --output text
```

**Esperado:** `2026 11 25`.

Para não esperar a hora cheia, dá para disparar a Step Function manualmente pela console (`lo5-datamesh-addpartition-sfn` → *Start execution*, reaproveitando o input da última execução agendada).

### 4.1 Conferir no Glue pela console da AWS

**Onde a tabela fica:** foi criada com `catalog_id = 773683090477` → está no catálogo da **conta de controle** (dev), **não** na conta de dev da LO5 (`435908583578`).

| Conta logada | Onde procurar |
|---|---|
| `773683090477` (controle) | Glue → Databases → `db_source_fraudeepld_limitesoperacionais_sor_01` |
| `435908583578` (dev LO5) | Glue → Databases → database do **resource link** (valor de `sor_db_name_resource_link` no tfvars de dev do datacatalog; aparece com ícone de link / "Shared resource") |
| outra | conta errada |

Região sempre **South America (São Paulo) sa-east-1**.

**Tabela:**
1. **AWS Glue → Data Catalog → Databases** → abrir o database da tabela acima.
2. Em **Tables**, abrir **`tblo5046_limi_opel_flxl`**.
3. Aba **Schema**: 8 colunas (`cod_idef_pess`, `num_unic_cont`, `nom_situ_limi_flxl`, `dat_hor_incu_rgto`, `dat_hor_expu`, `vlr_sltd` `decimal(10,2)`, `des_moti`, `des_ctto`) e partition keys `ano`, `mes`, `dia` (`int`).
4. **Table details**: Location `s3://itau-corp-sor-sa-east-1-435908583578/tblo5046_limi_opel_flxl/`, Classification `parquet`.

**Partições** (após o teste + hora cheia):
1. Na tabela, aba **Partitions** (ou **View partitions**).
2. Esperado: `ano=2026`, `mes=11`, `dia=25`.
3. Vazio → conferir arquivo no S3 (passo 3); **Step Functions → `lo5-datamesh-addpartition-sfn` → Executions** (última deve estar *Succeeded*); se falhou, DLQ da fila `lo5-datamesh-addpartiton-phoenix` no **SQS**.

**Permissão (Lake Formation, conta de controle):**
**Lake Formation → Permissions → Data permissions** → filtrar Table = `tblo5046_limi_opel_flxl` → esperado: `lo5-datamesh-execution-role` com `SELECT`, `ALTER`, `INSERT`, `DESCRIBE`.

#### Tabela não aparece na console

Teste de controle: no mesmo lugar, a **`tblo5_consentimento_personalizacao`** aparece?

- **Ela aparece e a nossa não** → a Parte 1 não foi aplicada nesse ambiente:
  1. Repositório datacatalog → **Actions** → última execução da branch → no apply, procurar
     `aws_glue_catalog_table.tblo5046_limi_opel_flxl: Creation complete` e
     `aws_lakeformation_permissions.permissao_tblo5046_limi_opel_flxl: Creation complete`.
  2. Se só rodou o plan (sem `Apply complete`), o apply ainda não aconteceu.
  3. Em hom/prod a tabela só existe depois do **merge na `main`**.
- **Ela também não aparece** → problema de **onde/como** se está olhando, não da tabela:
  1. Conferir **conta e região** (tabela acima).
  2. Na conta de dev, usar o database do **resource link**.
  3. Se a conta está certa e mesmo assim nada aparece → **Lake Formation esconde tabelas sem `DESCRIBE`** para a sua role. Confirmar pelo **CloudShell**:

     ```bash
     aws glue get-tables --region sa-east-1 --catalog-id 773683090477 \
       --database-name db_source_fraudeepld_limitesoperacionais_sor_01 \
       --query "TableList[].Name"
     ```

     - `AccessDenied` / lista vazia → falta permissão para a sua role: pedir `DESCRIBE` no Lake Formation ao time/admin do Data Mesh (não usar a `lo5-datamesh-execution-role`, que é da pipeline).
     - Lista as tabelas → elas existem; o problema é só a visualização na console.
  4. Prova definitiva independente da console: o log `Creation complete` do apply da Parte 1.

**Atalho pelo Athena** (se a tabela aparece no Glue):

```sql
SHOW PARTITIONS db_source_fraudeepld_limitesoperacionais_sor_01.tblo5046_limi_opel_flxl;
```

(na conta de dev, trocar pelo nome do database do resource link)

## 5. Consultar no Athena

> Requer **DESCRIBE + SELECT no Lake Formation** da conta de controle para a **sua role** (ver 5.3). Sem isso a tabela não aparece.

### 5.1 Passo a passo (console da conta 3578, sa-east-1)

1. **Amazon Athena → Query editor**.
2. **Workgroup** (canto superior direito): usar o do time (LO5/Data Mesh) se existir — já vem com local de resultados e permissões.
3. Se aparecer aviso de **query result location**: **Settings → Manage** → *Location of query result* = um caminho S3 da sua conta onde você possa gravar (bucket com "athena"/"query-results" no nome) → **Save**.
4. Painel esquerdo: **Data source** = `AwsDataCatalog`; **Database** = o do **resource link** (valor de `sor_db_name_resource_link` no tfvars de dev do datacatalog). O `db_source_fraudeepld_limitesoperacionais_sor_01` existe só na conta de controle.
5. Rodar (com o database selecionado não precisa prefixar):

```sql
SHOW TABLES;
SHOW PARTITIONS tblo5046_limi_opel_flxl;

SELECT *
FROM tblo5046_limi_opel_flxl
WHERE ano = 2026 AND mes = 11 AND dia = 25
  AND cod_idef_pess = 'TESTE-0001';
```

**Esperado:** 1 linha com todos os campos preenchidos e `vlr_sltd = 100.50`.

### 5.2 Problemas comuns no Athena

| Sintoma | Causa | Solução |
|---|---|---|
| Botão **Run** desabilitado | sem *query result location*; workgroup errado/desabilitado; editor vazio ou sem database | configurar o local de resultados (passo 3); trocar o workgroup; selecionar o database |
| `Table not found` / `SHOW TABLES` sem a tabela | Lake Formation **esconde** tabelas sem `DESCRIBE` (não diz "acesso negado") ou database errado | conferir o database (resource link, não `default`); pedir acesso (5.3) |
| `SHOW TABLES` vazio — **nem a `tblo5_consentimento_personalizacao`** aparece | sua role não tem permissão em **nada** do database | pedir acesso ao **database** (5.3) |
| aparece a `consentimento` mas não a `tblo5046` | permissão só nas tabelas antigas | pedir acesso só na tabela nova |
| `Insufficient Lake Formation permission(s)` | falta `SELECT` | pedir acesso (5.3) |
| `SHOW PARTITIONS` vazio / `SELECT` sem linhas | add-partition ainda não rodou | esperar hora cheia; ver Step Function |
| linha com campos **nulos** | chave do JSON ≠ nome da coluna | corrigir payload |

### 5.3 Pedido de acesso (time de plataforma Data Mesh)

O acesso é concedido no Lake Formation da **conta de controle** — não dá para liberar pela conta 3578.

> Olá! Preciso de permissão **DESCRIBE** e **SELECT** no Lake Formation da conta de controle **`773683090477`** (dev) para o database **`db_source_fraudeepld_limitesoperacionais_sor_01`** — incluindo as tabelas `tblo5046_limi_opel_flxl` e `tblo5_consentimento_personalizacao` — para a minha role **`<NOME_DA_ROLE>`** na conta **`435908583578`**.
> Objetivo: consultar via Athena (resource link `<VALOR_DE_sor_db_name_resource_link>`) para validar a ingestão da nova tabela em dev.

**`<NOME_DA_ROLE>`:** canto superior direito da console → clicar no usuário → trecho depois de `assumed-role/` (ou `role/`) até a próxima `/`. Não pedir para a `lo5-datamesh-execution-role` (é a role da pipeline).

> Também é possível não ter acesso nenhum à conta de controle pelo portal SSO — é o normal para devs; o caminho é o resource link + permissão no Lake Formation.

### 5.4 Alternativa sem Athena: ler o próprio Parquet

1. S3 → selecionar o `.parquet` → **Download**.
2. Abrir localmente:

```python
import pandas as pd
print(pd.read_parquet("arquivo.parquet"))
```

ou DuckDB: `SELECT * FROM 'arquivo.parquet';`

Mostra se os campos foram convertidos corretamente (não prova a partição no Glue — para isso, Step Function *Succeeded*).

## 6. Teste negativo do filtro (opcional)

Publicar com outro `event_type` e confirmar que **não** chega arquivo novo no prefixo da tabela:

```bash
aws sns publish --region sa-east-1 \
  --topic-arn arn:aws:sns:sa-east-1:435908583578:lo5-data-ingestion-topic \
  --message '{"cod_idef_pess":"TESTE-NEG"}' \
  --message-attributes '{"event_type":{"DataType":"String","StringValue":"tabela_inexistente"}}'
```

## Troubleshooting

| Sintoma | Onde olhar | Causa provável |
|---|---|---|
| `publish` dá `AuthorizationError` | IAM da role usada | falta `sns:Publish` no tópico (4.3) |
| Nada chega no S3 | CloudWatch → Metrics → SNS → Topic Metrics → `NumberOfNotificationsFilteredOut` / `Failed` / `Delivered` | `FilteredOut` = `event_type` diferente do filtro; `Failed` = permissão da role da assinatura |
| Nada chega no S3 | log group `Phoenix-events/delivery_stream_limites_tblo5046_limi_opel_flxl` | erro de entrega do Firehose |
| Alarme `DataFormatConversionFailed` | logs do Firehose | JSON fora do schema do Glue (nome/tipo de campo) |
| Alarme `KMSKeyAccessDenied` | logs do Firehose | role sem acesso à chave KMS do bucket |
| Arquivo no S3, mas Athena vazio | `get-partitions` (passo 4) | add-partition ainda não rodou ou falhou (ver execução da Step Function e DLQ da fila `lo5-datamesh-addpartiton-phoenix`) |
| Athena retorna colunas nulas | payload enviado | chaves do JSON diferentes dos nomes das colunas |
| Erro de permissão no Athena/Glue | Lake Formation | permissão da Parte 1 não aplicada para a role |

## Limpeza

O registro `TESTE-0001` fica na tabela de dev. Se precisar remover, apague o objeto no S3 do prefixo correspondente (confirme com o time antes, pois é tabela governada).

## Registro do teste em dev (2026-11-25)

| Etapa | Status | Prova |
|---|---|---|
| Parte 1 — tabela + permissão da pipeline | ✅ | CloudTrail `CreateTable` sem `errorCode` (2 eventos) |
| Parte 2 — SNS → Firehose | ✅ | `NumberOfMessagesPublished` = 1, `NumberOfNotificationsDelivered` = 1 |
| Firehose → S3 | ✅ | arquivo no bucket `itau-corp-sor-sa-east-1-435908583578` |
| Parte 3 — partição | ⏳ | Step Function `lo5-datamesh-addpartition-sfn` *Succeeded* após hora cheia |
| Athena | ⏳ | bloqueado: role pessoal sem DESCRIBE/SELECT no Lake Formation (nem `consentimento` aparece) — pedido 5.3 |

**Problemas encontrados no deploy (para não repetir):**
- `permissions.tf`: `depends_on = [aws_glue_catalog_tblo5046_limi_opel_fxl]` → `Invalid reference`. Correto: `[aws_glue_catalog_table.tblo5046_limi_opel_flxl]` (faltava `_table.` e `fxl` ≠ `flxl`).
- connector-events: conta errada na `location` (`435988583578`) → `S3 Bucket ... does not exist`. Correto: dev `435908583578`, prod `159000176689`.
- connector-events: trocar a chave do mapa (`tblo5046...` → `connector_tblo5046...`) depois de um apply parcial → `ResourceAlreadyExistsException: The specified log group already exists` (cria o novo e destrói o antigo em paralelo, mesmo nome). Solução: re-run. **Não renomear chave de `for_each` depois de aplicar.**

> O Athena não bloqueia a entrega: com a Step Function *Succeeded*, seguir com o merge para hom/prod e usar o Athena como conferência final quando o acesso sair.

## Depois de validar em dev

- [ ] Configurar a aplicação produtora (BFF/serviço de Limite Flexível) para publicar com o mesmo formato
- [ ] Garantir `sns:Publish` para a role da aplicação em dev/hom/prod
- [ ] Merge das 3 partes na ordem datacatalog → connector-events → add-partition (hom/prod)
- [ ] Repetir este roteiro em hom trocando conta (`727471073552`) e catalog (`827556317157`)
