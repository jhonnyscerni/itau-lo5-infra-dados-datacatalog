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
> Se nada chegar no S3: no tópico, aba **Monitoring**, métrica **NumberOfNotificationsFilteredOut**. Se subiu, o problema está no atributo `event_type`.

## 3. Conferir o arquivo no S3 (~60s depois — `buffer_interval`)

```bash
aws s3 ls --recursive s3://itau-corp-sor-sa-east-1-435908583578/tblo5046_limi_opel_flxl/ | tail -5
```

**Esperado:** arquivo novo em `.../ano=2026/mes=11/dia=25/...` (ou no formato de prefixo usado pela `tblo5_consentimento_personalizacao`).

> **Antes do teste o prefixo não existe — é normal.** Criar a tabela no Glue não cria nada no S3 (o Glue só guarda o metadado/`location`), e no S3 não existem pastas de verdade: o "diretório" `tblo5046_limi_opel_flxl/` só aparece quando o **primeiro arquivo** é gravado pelo Firehose. O bucket `itau-corp-sor-sa-east-1-435908583578` em si já deve existir (é o mesmo da `tblo5_consentimento_personalizacao`). Se não aparecer na lista de buckets, pode ser falta de `s3:ListAllMyBuckets` — abrir direto: `https://s3.console.aws.amazon.com/s3/buckets/itau-corp-sor-sa-east-1-435908583578?region=sa-east-1`.

Se não aparecer em até 5 minutos → seção **Troubleshooting**.

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

```sql
SELECT *
FROM db_source_fraudeepld_limitesoperacionais_sor_01.tblo5046_limi_opel_flxl
WHERE ano = 2026 AND mes = 11 AND dia = 25
  AND cod_idef_pess = 'TESTE-0001';
```

**Esperado:** 1 linha com todos os campos preenchidos e `vlr_sltd = 100.50`.

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
| Nada chega no S3 | métrica `NumberOfNotificationsFilteredOut` do tópico | `event_type` diferente do filtro |
| Nada chega no S3 | log group `Phoenix-events/delivery_stream_limites_tblo5046_limi_opel_flxl` | erro de entrega do Firehose |
| Alarme `DataFormatConversionFailed` | logs do Firehose | JSON fora do schema do Glue (nome/tipo de campo) |
| Alarme `KMSKeyAccessDenied` | logs do Firehose | role sem acesso à chave KMS do bucket |
| Arquivo no S3, mas Athena vazio | `get-partitions` (passo 4) | add-partition ainda não rodou ou falhou (ver execução da Step Function e DLQ da fila `lo5-datamesh-addpartiton-phoenix`) |
| Athena retorna colunas nulas | payload enviado | chaves do JSON diferentes dos nomes das colunas |
| Erro de permissão no Athena/Glue | Lake Formation | permissão da Parte 1 não aplicada para a role |

## Limpeza

O registro `TESTE-0001` fica na tabela de dev. Se precisar remover, apague o objeto no S3 do prefixo correspondente (confirme com o time antes, pois é tabela governada).

## Depois de validar em dev

- [ ] Configurar a aplicação produtora (BFF/serviço de Limite Flexível) para publicar com o mesmo formato
- [ ] Garantir `sns:Publish` para a role da aplicação em dev/hom/prod
- [ ] Merge das 3 partes na ordem datacatalog → connector-events → add-partition (hom/prod)
- [ ] Repetir este roteiro em hom trocando conta (`727471073552`) e catalog (`827556317157`)
