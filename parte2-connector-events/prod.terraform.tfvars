# Componentes CONNECTOR
connector_events = {
  connector_template_sns = {
    type_connector = "sns"
    # SNS topic
    sns_topic = {
      event_sns_subscription_topic_name          = "lo5-data-ingestion-topic"
      event_sns_subscription_filter_policy       = "{\"event_type\": [\"tblo5_consentimento_personalizacao\"]}"
      event_sns_subscription_filter_policy_scope = "MessageAttributes"
    }
    # Kinesis Firehose
    event = {
      name                           = "delivery_stream_limites_tblo5_consentimento_personalizacao"
      role_name                      = "iamsr/lo5-datamesh-execution-role"
      buffer_interval                = 60
      buffer_size                    = 128
      enable_dynamic_partitioning    = false
      timestamp_partition_field_name = "event_timestamp"
    }
    # Table
    data_table = {
      database_name = "db_source_fraudeepld_limitesoperacionais_sor_01"
      table = {
        table_name     = "tblo5_consentimento_personalizacao"
        location       = "s3://itau-corp-sor-sa-east-1-159000176689/tblo5_consentimento_personalizacao"
        partition_keys = ["ano", "mes", "dia"]
      }
      catalog_id = "973136190634" # ID do catalogo onde a tabela se encontra. Nao editar esse valor para uso do db_source
    }
    # Caso deseje personalizar metricas de finops e alertas, verificar valores no arquivo variables.tf
  }

  connector_tblo5046_limi_opel_flxl = {
    type_connector = "sns"
    # SNS topic
    sns_topic = {
      event_sns_subscription_topic_name          = "lo5-data-ingestion-topic"
      event_sns_subscription_filter_policy       = "{\"event_type\": [\"tblo5046_limi_opel_flxl\"]}"
      event_sns_subscription_filter_policy_scope = "MessageAttributes"
    }
    # Kinesis Firehose
    event = {
      name                           = "delivery_stream_limites_tblo5046_limi_opel_flxl"
      role_name                      = "iamsr/lo5-datamesh-execution-role"
      buffer_interval                = 60
      buffer_size                    = 128
      enable_dynamic_partitioning    = false
      timestamp_partition_field_name = "event_timestamp"
    }
    # Table
    data_table = {
      database_name = "db_source_fraudeepld_limitesoperacionais_sor_01"
      table = {
        table_name     = "tblo5046_limi_opel_flxl"
        location       = "s3://itau-corp-sor-sa-east-1-159000176689/tblo5046_limi_opel_flxl"
        partition_keys = ["ano", "mes", "dia"]
      }
      catalog_id = "973136190634"
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
  Environment         = "prod"                                                     # Ambiente
  sigla               = "LO5"                                                     # Sigla da aplicacao. Obrigatorio para o SQS
  comunidade          = "PLATAFORMAS E JORNADAS DE DAILY BANKING"                 # Nome da comunidade. Obrigatorio para o SQS
  squad               = "GESTAO DE LIMITES TRANSACIONAIS 1"                       # Nome da squad. Obrigatorio para o SQS
  nomeproduto         = "Limitesoperacionais"                                     # Nome do produto. Obrigatorio para o SQS
}
