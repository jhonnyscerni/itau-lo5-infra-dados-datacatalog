connector_events_add_partition = {
  connector_events_add_partition_1 = {
    # Table
    data_table = {
      database_name = "db_source_fraudeepld_limitesoperacionais_sor_01" # Nome do database
      catalog_id    = "827556317157"                                      # ID do catalogo onde a tabela se encontra. Nao editar
      tables = [
        {
          table_name     = "tblo5_consentimento_personalizacao",
          location       = "s3://itau-corp-sor-sa-east-1-727471073552/tblo5_consentimento_personalizacao",
          partition_keys = ["ano", "mes", "dia"]
        },
        {
          table_name     = "tblo5046_limi_opel_flxl",
          location       = "s3://itau-corp-sor-sa-east-1-727471073552/tblo5046_limi_opel_flxl",
          partition_keys = ["ano", "mes", "dia"]
        }
      ]
    }
    # SNS
    sqs_notification = {
      queue_name                    = "lo5-datamesh-addpartiton-phoenix" # Nome da fila SQS
      max_message_size              = 262144                             # Tamanho maximo da mensagem em bytes
      message_retention_seconds     = 432000                             # Tempo de retencao da mensagem na fila em segundos
      max_receive_count             = 10                                 # Numero maximo de tentativas
      max_message_size_dlq          = 262144                             # Tamanho maximo da mensagem da DLQ em bytes
      message_retention_seconds_dlq = 432000                             # Tempo de retencao da mensagem na DLQ em segundos
    }
    # Step Functions
    schedule_data_partition = {
      event_bridge_rule_name                      = "lo5-datamesh-addpartition-rule"
      state_machine_name                          = "lo5-datamesh-addpartition-sfn"
      rule_schedule_expression_sfn_data_partition = "cron(0 * * * ? *)"
      execution_role_name                         = "iamsr/lo5-datamesh-execution-role"
    }
  }
}

# TAGS
tags = {
  owner-contact-email = "leda.cruz@itau-unibanco.com.br"                          # Email do owner da conta
  tech-team-email     = "squad_Gestao_Limites_Operacionais_1@correio.itau.com.br" # Email da squad
  journey             = "Limitesoperacionais"                                     # Nome da jornada
  event               = "inclusão"                                                # Nome de identificacao do evento
  datamesh            = true
  Environment         = "dev"                                                     # Ambiente (mantido como esta no repo)
  sigla               = "LO5"                                                     # Sigla da aplicacao. Obrigatorio para o SQS
  comunidade          = "PLATAFORMAS E JORNADAS DE DAILY BANKING"                 # Nome da comunidade. Obrigatorio para o SQS
  squad               = "GESTAO DE LIMITES TRANSACIONAIS 1"                       # Nome da squad. Obrigatorio para o SQS
  nomeproduto         = "Limitesoperacionais"                                     # Nome do produto. Obrigatorio para o SQS
}
