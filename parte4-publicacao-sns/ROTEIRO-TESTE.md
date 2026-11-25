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

## 3. Conferir o arquivo no S3 (~60s depois — `buffer_interval`)

```bash
aws s3 ls --recursive s3://itau-corp-sor-sa-east-1-435908583578/tblo5046_limi_opel_flxl/ | tail -5
```

**Esperado:** arquivo novo em `.../ano=2026/mes=11/dia=25/...` (ou no formato de prefixo usado pela `tblo5_consentimento_personalizacao`).

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
