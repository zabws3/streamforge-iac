
# ==========================================
# StreamForge IaC - Makefile
# ==========================================

TF_DIR := terraform/environments/dev
TF_VAR_FILE := dev.tfvars
PRO_TF_DIR := terraform/environments/pro
PRO_TF_VAR_FILE := pro.tfvars

.PHONY: help setup demo dev-init dev-validate dev-plan dev-up dev-deploy dev-destroy dev-output dev-ps dev-logs web-logs lb-logs grafana-logs dev-restart pro-init pro-validate pro-plan pro-up pro-deploy pro-destroy pro-output pro-ps

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
	@echo " make demo           Ejecutar demo interactiva de resiliencia"
	@echo " make dev-destroy    Destruir DEV"
	@echo " make dev-output     Mostrar outputs"
	@echo " make dev-ps         Ver contenedores"
	@echo " make dev-logs      Logs de los servicios"
	@echo " make web-logs      Logs Web 1"
	@echo " make lb-logs       Logs Load Balancer"
	@echo " make grafana-logs  Logs Grafana"
	@echo " make dev-restart   Destruir y reconstruir DEV"
	@echo " make pro-init      Inicializar Terraform PRO"
	@echo " make pro-validate  Validar configuracion PRO"
	@echo " make pro-plan      Mostrar plan PRO"
	@echo " make pro-up        Inicializar y aplicar PRO"
	@echo " make pro-deploy    Generar plan y aplicar PRO"
	@echo " make pro-destroy   Destruir PRO"
	@echo " make pro-output    Mostrar outputs PRO"
	@echo " make pro-ps        Ver contenedores PRO"
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

demo:
	./demo.sh

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

pro-init:
	terraform -chdir=$(PRO_TF_DIR) init

pro-validate:
	terraform -chdir=$(PRO_TF_DIR) validate

pro-plan:
	terraform -chdir=$(PRO_TF_DIR) plan -var-file=$(PRO_TF_VAR_FILE)

pro-up:
	terraform -chdir=$(PRO_TF_DIR) init
	terraform -chdir=$(PRO_TF_DIR) apply -var-file=$(PRO_TF_VAR_FILE)

pro-deploy:
	terraform -chdir=$(PRO_TF_DIR) init
	terraform -chdir=$(PRO_TF_DIR) plan -var-file=$(PRO_TF_VAR_FILE) -out=tfplan
	terraform -chdir=$(PRO_TF_DIR) apply tfplan

pro-destroy:
	terraform -chdir=$(PRO_TF_DIR) destroy -var-file=$(PRO_TF_VAR_FILE)

pro-output:
	terraform -chdir=$(PRO_TF_DIR) output

pro-ps:
	docker ps -a --filter name=pro_ --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
