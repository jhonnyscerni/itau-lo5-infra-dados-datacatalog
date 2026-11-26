resource "aws_glue_catalog_table" "tblo5046_limi_opel_flxl" {
  catalog_id    = local.control_account_id
  database_name = var.sor_db_name_source
  name          = "tblo5046_limi_opel_flxl"
  table_type    = "EXTERNAL_TABLE"
  parameters = {
    classification = "parquet"
  }
  retention = 0

  storage_descriptor {
    input_format              = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format             = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"
    compressed                = false
    stored_as_sub_directories = false
    location                  = "${var.sor_s3bucket}/tblo5046_limi_opel_flxl/"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
      parameters            = {}
    }

    columns {
      name       = "cod_idef_pess"
      type       = "string"
      comment    = "Codigo identificador da pessoa"
      parameters = {}
    }

    columns {
      name       = "dat_hor_incu_rgto"
      type       = "string"
      comment    = "Data e hora de inclusao do registro"
      parameters = {}
    }

    columns {
      name       = "cod_idef_pend_forl"
      type       = "string"
      comment    = "Codigo identificador da pendencia de formalizacao"
      parameters = {}
    }

    columns {
      name       = "dat_hor_expu"
      type       = "string"
      comment    = "Data e hora de expiracao (TTL)"
      parameters = {}
    }

    columns {
      name       = "des_detl_moti_soli"
      type       = "string"
      comment    = "Descricao detalhada do motivo da solicitacao"
      parameters = {}
    }

    columns {
      name       = "des_moti_soli"
      type       = "string"
      comment    = "Descricao do motivo da solicitacao"
      parameters = {}
    }

    columns {
      name       = "nom_ctto_soli"
      type       = "string"
      comment    = "Nome do contato da solicitacao"
      parameters = {}
    }

    columns {
      name       = "nom_situ_limi_flxl"
      type       = "string"
      comment    = "Situacao do limite flexivel"
      parameters = {}
    }

    columns {
      name       = "num_unic_cont"
      type       = "string"
      comment    = "Numero unico da conta"
      parameters = {}
    }

    columns {
      name       = "vlr_sltd_clie"
      type       = "decimal(10,2)"
      comment    = "Valor solicitado pelo cliente"
      parameters = {}
    }
  }

  partition_keys {
    name = "ano"
    type = "int"
  }

  partition_keys {
    name = "mes"
    type = "int"
  }

  partition_keys {
    name = "dia"
    type = "int"
  }
}
