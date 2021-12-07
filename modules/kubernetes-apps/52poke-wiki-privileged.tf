resource "kubernetes_service" "wiki_52poke_privileged" {
  metadata {
    name = "wiki-52poke-privileged"
  }

  spec {
    port {
      port = 80
    }

    selector = {
      app = "52poke-wiki-privileged"
    }
  }
}

resource "kubernetes_deployment" "wiki_52poke_privileged" {
  metadata {
    name = "52poke-wiki-privileged"
  }

  spec {
    selector {
      match_labels = {
        app = "52poke-wiki-privileged"
      }
    }

    template {
      metadata {
        labels = {
          app = "52poke-wiki-privileged"
        }
      }

      spec {
        node_selector = {
          "lke.linode.com/pool-id" = var.pool_ids[0]
        }

        affinity {
          pod_anti_affinity {
            required_during_scheduling_ignored_during_execution {
              label_selector {
                match_expressions {
                  key      = "app"
                  operator = "In"
                  values = [
                    "52poke-wiki",
                    "52poke-wiki-privileged"
                  ]
                }
              }

              topology_key = "kubernetes.io/hostname"
            }
          }
        }

        volume {
          name = "52poke-wiki-config"

          config_map {
            name = "52poke-wiki"
          }
        }

        volume {
          name = "mysql-user"

          secret {
            secret_name = "mysql-wiki"
          }
        }

        volume {
          name = "52poke-wiki-secret"

          secret {
            secret_name = "52poke-wiki"
          }
        }

        volume {
          name = "aws-s3"

          secret {
            secret_name = "aws-s3"
          }
        }

        volume {
          name = "aws-ses"

          secret {
            secret_name = "aws-ses"
          }
        }

        volume {
          name = "recaptcha"

          secret {
            secret_name = "recaptcha"
          }
        }

        container {
          name  = "52poke-wiki"
          image = "ghcr.io/mudkipme/mediawiki:latest"

          resources {
            requests = {
              cpu    = "400m"
              memory = "384Mi"
            }
          }

          port {
            container_port = 80
          }

          volume_mount {
            name       = "52poke-wiki-config"
            read_only  = true
            mount_path = "/home/52poke/wiki/LocalSettings.php"
            sub_path   = "LocalSettings.php"
          }

          volume_mount {
            name       = "mysql-user"
            read_only  = true
            mount_path = "/run/secrets/52w-db-user"
            sub_path   = "username"
          }

          volume_mount {
            name       = "mysql-user"
            read_only  = true
            mount_path = "/run/secrets/52w-db-password"
            sub_path   = "password"
          }

          volume_mount {
            name       = "52poke-wiki-secret"
            read_only  = true
            mount_path = "/run/secrets/52w-secret-key"
            sub_path   = "secretKey"
          }

          volume_mount {
            name       = "52poke-wiki-secret"
            read_only  = true
            mount_path = "/run/secrets/52w-upgrade-key"
            sub_path   = "upgradeKey"
          }

          volume_mount {
            name       = "aws-s3"
            read_only  = true
            mount_path = "/run/secrets/aws-s3-ak"
            sub_path   = "accessKeyID"
          }

          volume_mount {
            name       = "aws-s3"
            read_only  = true
            mount_path = "/run/secrets/aws-s3-sk"
            sub_path   = "secretAccessKey"
          }

          volume_mount {
            name       = "aws-ses"
            read_only  = true
            mount_path = "/run/secrets/aws-smtp-ak"
            sub_path   = "accessKeyID"
          }

          volume_mount {
            name       = "aws-ses"
            read_only  = true
            mount_path = "/run/secrets/aws-smtp-sk"
            sub_path   = "secretAccessKey"
          }

          volume_mount {
            name       = "recaptcha"
            read_only  = true
            mount_path = "/run/secrets/recaptcha-site-key"
            sub_path   = "siteKey"
          }

          volume_mount {
            name       = "recaptcha"
            read_only  = true
            mount_path = "/run/secrets/recaptcha-secret-key"
            sub_path   = "secretKey"
          }

          image_pull_policy = "Always"
        }

        container {
          name  = "poolcounter"
          image = "mudkip/poolcounter"

          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
          }

          port {
            container_port = 7531
          }
        }
      }
    }

    strategy {
      type = "Recreate"
    }
  }
}