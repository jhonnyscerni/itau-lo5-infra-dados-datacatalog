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
