
# ==========================================
# StreamForge IaC - Makefile
# ==========================================

TF_DIR := terraform/environments/dev
TF_VAR_FILE := dev.tfvars

.PHONY: help setup dev-init dev-validate dev-plan dev-up dev-deploy dev-destroy dev-output dev-ps dev-logs web-logs lb-logs grafana-logs dev-restart

help:
	@echo ""
	@echo " StreamForge IaC - Comandos disponibles"
	@echo " -----------------------------------"
	@echo " make dev-init       Inicializar Terraform"
	@echo " make dev-validate   Validar configuracion"
	@echo " make dev-plan       Mostrar plan"
	@echo " make dev-up         Levantar DEV"
	@echo " make dev-deploy    Plan y aplicar cambios DEV"
	@echo " make setup          Preparar infraestructura DEV y buckets MinIO"
	@echo " make dev-destroy    Destruir DEV"
	@echo " make dev-output     Mostrar outputs"
	@echo " make dev-ps         Ver contenedores"
	@echo " make dev-logs      Logs de los servicios"
	@echo " make web-logs      Logs Web 1"
	@echo " make lb-logs       Logs Load Balancer"
	@echo " make grafana-logs  Logs Grafana"
	@echo " make dev-restart   Destruir y reconstruir DEV"
	@echo ""

dev-init:
	terraform -chdir=$(TF_DIR) init

dev-validate:
	terraform -chdir=$(TF_DIR) validate

dev-plan:
	terraform -chdir=$(TF_DIR) plan -var-file=$(TF_VAR_FILE)

dev-up:
	terraform -chdir=$(TF_DIR) init
	terraform -chdir=$(TF_DIR) apply -var-file=$(TF_VAR_FILE)

dev-deploy:
	terraform -chdir=$(TF_DIR) init
	terraform -chdir=$(TF_DIR) plan -var-file=$(TF_VAR_FILE) -out=tfplan
	terraform -chdir=$(TF_DIR) apply tfplan

setup: dev-up

dev-destroy:
	terraform -chdir=$(TF_DIR) destroy -var-file=$(TF_VAR_FILE)

dev-output:
	terraform -chdir=$(TF_DIR) output

dev-ps:
	docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

dev-logs:
	docker logs dev_web_1
	docker logs dev_web_2
	docker logs dev_load_balancer
	docker logs dev_database
	docker logs dev_redis

web-logs:
	docker logs -f dev_web_1

lb-logs:
	docker logs -f dev_load_balancer

grafana-logs:
	docker logs -f dev_grafana

dev-restart:
	terraform -chdir=$(TF_DIR) destroy -var-file=$(TF_VAR_FILE)
	terraform -chdir=$(TF_DIR) apply -var-file=$(TF_VAR_FILE)
