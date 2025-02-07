provider "mysql" {
  endpoint = "mariadb:3306"
}

resource "mysql_database" "mysql-52poke-wiki" {
  name                  = "52poke_wiki"
  default_character_set = "utf8"
  default_collation     = "utf8_general_ci"

  lifecycle {
    prevent_destroy = true
  }
}

resource "mysql_database" "mysql-52poke-www" {
  name                  = "52poke"
  default_character_set = "utf8"
  default_collation     = "utf8_general_ci"

  lifecycle {
    prevent_destroy = true
  }
}

resource "mysql_database" "mysql-makeawish" {
  name                  = "makeawish"
  default_character_set = "utf8mb4"
  default_collation     = "utf8mb4_general_ci"

  lifecycle {
    prevent_destroy = true
  }
}

resource "mysql_user" "wiki" {
  user               = "wiki"
  host               = "%"
  plaintext_password = var.mysql_wiki_password
}

resource "mysql_user" "www" {
  user               = "www"
  host               = "%"
  plaintext_password = var.mysql_www_password
}

resource "mysql_user" "makeawish" {
  user               = "makeawish"
  host               = "%"
  plaintext_password = var.mysql_makeawish_password
}

resource "mysql_grant" "wiki" {
  user       = mysql_user.wiki.user
  host       = "%"
  database   = mysql_database.mysql-52poke-wiki.name
  privileges = ["ALL"]
}

resource "mysql_grant" "www" {
  user       = mysql_user.www.user
  host       = "%"
  database   = mysql_database.mysql-52poke-www.name
  privileges = ["ALL"]
}

resource "mysql_grant" "makeawish" {
  user       = mysql_user.makeawish.user
  host       = "%"
  database   = mysql_database.mysql-makeawish.name
  privileges = ["ALL"]
}
