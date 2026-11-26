resource "aws_lakeformation_permissions" "permissao_tblo5046_limi_opel_flxl" {
  permissions = ["SELECT", "ALTER", "INSERT", "DESCRIBE"]
  principal   = var.minha_role1_arn

  table {
    database_name = var.sor_db_name_source
    name          = "tblo5046_limi_opel_flxl"
    catalog_id    = local.control_account_id
  }

  depends_on = [aws_glue_catalog_table.tblo5046_limi_opel_flxl]
}

# Role de consulta (Athena) - leitura da tabela para validacao.
# Preencher no tfvars do ambiente; vazio = nao cria a permissao.
# Role SSO: usar o ARN SEM o path "aws-reserved/sso.amazonaws.com/<regiao>/"
# Ex.: arn:aws:iam::727471073552:role/AWSReservedSSO_<NOME>_<HASH>
variable "minha_role_consulta_arn" {
  type        = string
  default     = ""
  description = "ARN da role que consulta a tabela tblo5046_limi_opel_flxl via Athena"
}

resource "aws_lakeformation_permissions" "consulta_tblo5046_limi_opel_flxl" {
  count = var.minha_role_consulta_arn == "" ? 0 : 1

  permissions = ["SELECT", "DESCRIBE"]
  principal   = var.minha_role_consulta_arn

  table {
    database_name = var.sor_db_name_source
    name          = "tblo5046_limi_opel_flxl"
    catalog_id    = local.control_account_id
  }

  depends_on = [aws_glue_catalog_table.tblo5046_limi_opel_flxl]
}
