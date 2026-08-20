SHELL := /bin/bash
.DEFAULT_GOAL := help

PIP_COMPILE := uv pip compile --quiet --generate-hashes --strip-extras --python-platform=linux

##@ Setup

.PHONY: init init-meltano

init: upgrade-requirements sync-venv dbt-deps ##@Setup Init main dev environment (dbt + dev tools)
	@echo "Dev environment ready"

init-meltano: upgrade-requirements sync-venv-meltano meltano-install ##@Setup Init meltano dev environment

init-venv:
	uv venv --python 3.13 --clear venv

sync-venv: init-venv ##@Setup Sync main venv from lockfile
	uv pip sync --python venv/bin/python3 requirements/main.txt

init-venv-meltano:
	uv venv --python 3.10 --clear venv-meltano

sync-venv-meltano: init-venv-meltano ##@Setup Sync meltano venv from lockfile
	uv pip sync --python venv-meltano/bin/python3 requirements/meltano.txt

##@ Dependencies

.PHONY: upgrade-requirements

upgrade-requirements: ##@Dependencies Recompile all lockfiles
	$(PIP_COMPILE) --python-version=3.13 requirements/dbt.in --output-file requirements/dbt.txt
	$(PIP_COMPILE) --python-version=3.10 requirements/meltano.in --output-file requirements/meltano.txt
	$(PIP_COMPILE) --python-version=3.13 requirements/main.in --output-file requirements/main.txt

##@ dbt

.PHONY: dbt-deps dbt-dev dbt-run dbt-test

DBT        := venv/bin/dbt
DBT_DIRS   := --project-dir dbt --profiles-dir dbt
DBT_TARGET ?= dev

dbt-deps: ##@dbt Install dbt packages
	$(DBT) deps $(DBT_DIRS)

dbt-run: ##@dbt Run dbt (DBT_TARGET=prod make dbt-run to target prod)
	$(DBT) run $(DBT_DIRS) --target $(DBT_TARGET)

dbt-test: ##@dbt Run dbt tests
	$(DBT) test $(DBT_DIRS) --target $(DBT_TARGET)

##@ Meltano

.PHONY: meltano-install meltano-run

TAP ?= tap-xxx

MELTANO     := venv-meltano/bin/meltano --cwd meltano
MELTANO_ENV ?= dev

ifeq ($(MELTANO_ENV),prod)
MELTANO_TARGET     := target-bigquery
MELTANO_LOG_CONFIG := logging-prod.yaml
else
MELTANO_TARGET     := target-bigquery-dev
MELTANO_LOG_CONFIG := logging-dev.yaml
endif

meltano-install: ##@Meltano Install all meltano plugins
	$(MELTANO) install

meltano-run: ##@Meltano Run a pipeline (TAP=tap-travel-perk MELTANO_ENV=prod make meltano-run)
	$(MELTANO) --environment $(MELTANO_ENV) --log-config $(MELTANO_LOG_CONFIG) run $(TAP) $(MELTANO_TARGET)


##@ Docker

.PHONY: docker-auth docker-build-meltano docker-push-meltano docker-build-dbt docker-push-dbt

REGISTRY   := europe-west1-docker.pkg.dev/lumapps-business-bi/bi
DBT_IMAGE  := $(REGISTRY)/dbt
TAP        ?= tap-travel-perk
DOCKER_ENV ?= dev

ifeq ($(DOCKER_ENV),prod)
_TAG            := latest
_MELTANO_LOADERS :=
else
_TAG            := dev
_MELTANO_LOADERS := --build-arg LOADERS="target-bigquery target-bigquery-dev"
endif

docker-auth: ##@Docker Authenticate Docker to Artifact Registry (run once)
	gcloud auth configure-docker europe-west1-docker.pkg.dev

docker-build-meltano: ##@Docker Build meltano image (TAP=tap-travel-perk make docker-build-meltano — DOCKER_ENV=prod to build prod)
	docker build --build-arg TAP_NAME=$(TAP) $(_MELTANO_LOADERS) \
		-f infra/docker/meltano.Dockerfile \
		-t $(REGISTRY)/meltano-$(TAP):$(_TAG) .

docker-push-meltano: ##@Docker Push meltano image (TAP=tap-travel-perk make docker-push-meltano — DOCKER_ENV=prod to push prod)
	docker push $(REGISTRY)/meltano-$(TAP):$(_TAG)

docker-build-dbt: ##@Docker Build dbt image (DOCKER_ENV=prod to build prod)
	docker build -f infra/docker/dbt.Dockerfile -t $(DBT_IMAGE):$(_TAG) .

docker-push-dbt: ##@Docker Push dbt image (DOCKER_ENV=prod to push prod)
	docker push $(DBT_IMAGE):$(_TAG)

##@ Terraform

.PHONY: tf-bootstrap tf-shared-init tf-shared-plan tf-shared-apply tf-pipeline-init tf-pipeline-plan tf-pipeline-apply secret-set

PIPELINE    ?= tap-travel-perk
PIPELINE_ENV ?= dev
SECRET      ?= api-key

tf-bootstrap: ##@Terraform Create the GCS remote state bucket (run once, before any terraform init)
	gcloud storage buckets create gs://lumapps-business-bi-terraform-state \
		--project=lumapps-business-bi \
		--location=EU \
		--uniform-bucket-level-access

tf-shared-init: ##@Terraform Init shared terraform
	terraform -chdir=infra/terraform/shared init

tf-shared-plan: ##@Terraform Plan shared terraform
	terraform -chdir=infra/terraform/shared plan

tf-shared-apply: ##@Terraform Apply shared terraform
	terraform -chdir=infra/terraform/shared apply

tf-pipeline-init: ##@Terraform Init a pipeline (PIPELINE=tap-travel-perk make tf-pipeline-init — PIPELINE_ENV=prod for prod)
	terraform -chdir=infra/terraform/pipelines/$(PIPELINE)/$(PIPELINE_ENV) init

tf-pipeline-plan: ##@Terraform Plan a pipeline (PIPELINE=tap-travel-perk make tf-pipeline-plan — PIPELINE_ENV=prod for prod)
	terraform -chdir=infra/terraform/pipelines/$(PIPELINE)/$(PIPELINE_ENV) plan

tf-pipeline-check-secrets: ##@Terraform Verify all pipeline secrets exist and have at least one version
	@echo "Checking secrets for pipeline '$(PIPELINE)'..."
	@secrets=$$(gcloud secrets list --project=lumapps-business-bi \
		--filter="name:$(PIPELINE)" --format="value(name)"); \
	if [ -z "$$secrets" ]; then \
		echo "No secrets found for pipeline '$(PIPELINE)' — skipping check."; \
	else \
		failed=0; \
		for secret in $$secrets; do \
			count=$$(gcloud secrets versions list $$secret \
				--project=lumapps-business-bi \
				--filter="state=ENABLED" \
				--format="value(name)" 2>/dev/null | wc -l | tr -d ' '); \
			if [ "$$count" -eq 0 ]; then \
				echo "ERROR: Secret '$$secret' has no enabled versions. Run:"; \
				echo "  make secret-set PIPELINE=$(PIPELINE) SECRET=<name>"; \
				failed=1; \
			else \
				echo "  OK: $$secret ($$count version(s))"; \
			fi; \
		done; \
		[ "$$failed" -eq 0 ] || exit 1; \
	fi

tf-pipeline-apply: tf-pipeline-check-secrets ##@Terraform Apply a pipeline (PIPELINE=tap-travel-perk make tf-pipeline-apply — PIPELINE_ENV=prod for prod)
	terraform -chdir=infra/terraform/pipelines/$(PIPELINE)/$(PIPELINE_ENV) apply

secret-set: ##@Terraform Set a secret value (PIPELINE=tap-travel-perk SECRET=api-key make secret-set — prompts for value)
	@read -s -p "Secret value for $(PIPELINE)-$(SECRET): " val && echo && \
	echo -n "$$val" | gcloud secrets versions add $(PIPELINE)-$(SECRET) \
		--project=lumapps-business-bi --data-file=-

##@ Help

help: ##@Help Show this help
	@awk 'BEGIN {FS = ":.*##@"; printf "Usage:\n  make \033[36m<target>\033[0m\n"} \
		/^[a-zA-Z0-9_%\/-]+:.*##@/ { split($$2, a, " "); printf "\n\033[1m%s\033[0m\n  \033[36m%-28s\033[0m %s\n", a[1], $$1, substr($$2, length(a[1])+2) }' \
		$(MAKEFILE_LIST)
