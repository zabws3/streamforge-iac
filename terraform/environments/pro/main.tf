moved {
  from = module.monitoring.local_file.alert_rules
  to   = module.alerts.local_file.alert_rules
}

moved {
  from = module.monitoring.docker_image.alertmanager
  to   = module.alerts.docker_image.alertmanager
}

moved {
  from = module.monitoring.docker_volume.alertmanager_data
  to   = module.alerts.docker_volume.alertmanager_data
}

moved {
  from = module.monitoring.docker_container.alertmanager
  to   = module.alerts.docker_container.alertmanager
}

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
    "${var.environment}_backend",
    "${var.environment}_host_storage"
  ]
  root_user     = var.minio_user
  root_password = var.minio_password
  api_port      = 9100
  console_port  = 9101

  depends_on = [module.network]
}

module "web" {
  source = "../../modules/web"

  environment = var.environment
  replicas    = 3
  image       = "streamforge-pro"

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
    SEED_DEMO_USERS  = "false"
    MINIO_ENDPOINT   = "http://${var.environment}-minio:9000"
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
    "${var.environment}_web_2",
    "${var.environment}_web_3"
  ]

  networks      = ["${var.environment}_frontend"]
  external_port = 8082

  depends_on = [module.web]
}

module "alerts" {
  source = "../../modules/alerts"

  environment             = var.environment
  monitoring_network      = "${var.environment}_monitoring"
  telegram_egress_network = "${var.environment}_frontend"
  web_containers = [
    "${var.environment}_web_1",
    "${var.environment}_web_2",
    "${var.environment}_web_3"
  ]
  cache_enabled             = true
  telegram_bot_token        = var.telegram_bot_token
  telegram_chat_id          = var.telegram_chat_id
  cpu_warning_threshold     = var.alert_cpu_warning_threshold
  cpu_critical_threshold    = var.alert_cpu_critical_threshold
  memory_warning_threshold  = var.alert_memory_warning_threshold
  memory_critical_threshold = var.alert_memory_critical_threshold
  depends_on                = [module.network]
}

module "monitoring" {
  source = "../../modules/monitoring"

  environment         = var.environment
  networks            = ["${var.environment}_monitoring"]
  grafana_networks    = ["${var.environment}_monitoring"]
  host_access_network = "${var.environment}_host_monitoring"
  alert_rules_path    = module.alerts.alert_rules_path
  alertmanager_target = module.alerts.alertmanager_target

  grafana_port           = 3002
  prometheus_port        = 9091
  grafana_admin_password = var.grafana_password

  depends_on = [module.network]
}
