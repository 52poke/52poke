provider "postgresql" {
  host     = "postgres"
  port     = 5432
  username = "postgres"
  password = var.postgres_password
  sslmode  = "disable"
}

resource "postgresql_database" "klinklang" {
  name = "klinklang"

  lifecycle {
    prevent_destroy = true
  }
}

resource "postgresql_role" "klinklang" {
  name     = "klinklang"
  login    = true
  password = var.postgres_klinklang_password
}

resource "postgresql_grant" "klinklang" {
  database    = postgresql_database.klinklang.name
  role        = postgresql_role.klinklang.name
  schema      = "public"
  object_type = "database"
  privileges  = ["ALL"]
}
