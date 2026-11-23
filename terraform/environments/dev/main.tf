module "network" {
  source      = "../../modules/network"
  environment = var.environment
}

module "database" {
  source = "../../modules/database"

  environment       = var.environment
  database_name     = var.database_name
  database_user     = var.database_user
  database_password = var.database_password
  root_password     = var.database_root_password
  networks          = ["${var.environment}_backend"]
  volume_name       = "${var.environment}_mysql_data"

  depends_on = [module.network]
}


module "cache" {
  source      = "../../modules/cache"
  environment = var.environment
  networks    = ["${var.environment}_backend"]

  depends_on = [module.network]
}

module "storage" {
  source = "../../modules/storage"

  environment = var.environment
  networks = [
    "${var.environment}_frontend",
    "${var.environment}_backend"
  ]
  root_user     = var.minio_user
  root_password = var.minio_password
  api_port      = 9000
  console_port  = 9001

  depends_on = [module.network]
}

module "web" {
  source = "../../modules/web"

  environment   = var.environment
  replicas      = 2
  image         = "streamforge-dev"
  internal_port = 3000

  networks = [
    "${var.environment}_frontend",
    "${var.environment}_backend"
  ]

  env_vars = {
    MYSQL_HOST     = "${var.environment}_database"
    MYSQL_PORT     = "3306"
    MYSQL_USER     = var.database_user
    MYSQL_PASSWORD = var.database_password
    MYSQL_DATABASE = var.database_name

    REDIS_HOST = "${var.environment}_redis"
    REDIS_PORT = "6379"

    SESSION_SECRET   = var.session_secret
    COOKIE_SECURE    = "false"
    MINIO_ENDPOINT   = "http://${var.environment}_minio:9000"
    MINIO_ACCESS_KEY = var.minio_user
    MINIO_SECRET_KEY = var.minio_password
  }

  depends_on = [
    module.database,
    module.cache,
    module.storage,
    module.network
  ]
}

module "load_balancer" {
  source = "../../modules/load_balancer"

  environment = var.environment

  web_containers = [
    "${var.environment}_web_1",
    "${var.environment}_web_2"
  ]

  networks      = ["${var.environment}_frontend"]
  external_port = 8081

  depends_on = [module.web]
}

module "monitoring" {
  source = "../../modules/monitoring"

  environment = var.environment
  networks    = ["${var.environment}_monitoring"]
  grafana_networks = [
    "${var.environment}_monitoring",
    "${var.environment}_frontend"
  ]

  web_containers = [
    "${var.environment}_web_1",
    "${var.environment}_web_2"
  ]

  grafana_port           = 3001
  grafana_admin_password = var.grafana_password

  depends_on = [module.network]
}
