provider "mysql" {
  endpoint = "mariadb-cache:3306"
  alias    = "mariadb_cache"
}

resource "mysql_database" "mysql-cache-52poke-wiki" {
  provider              = mysql.mariadb_cache
  name                  = "52poke_wiki"
  default_character_set = "utf8"
  default_collation     = "utf8_general_ci"

  lifecycle {
    prevent_destroy = true
  }
}

resource "mysql_user" "cache-wiki" {
  provider           = mysql.mariadb_cache
  user               = "wiki"
  host               = "%"
  plaintext_password = var.mysql_wiki_password
}

resource "mysql_grant" "cache-wiki" {
  provider   = mysql.mariadb_cache
  user       = mysql_user.cache-wiki.user
  host       = "%"
  database   = mysql_database.mysql-cache-52poke-wiki.name
  privileges = ["ALL"]
}