
old_deploy:
	@cd html && echo gcloud app deploy app.yaml cron.yaml
	@cd html && gcloud app deploy app.yaml

PROJECT_ID ?= wordpress-twbc-org
PROJECTNUM := $(shell gcloud projects describe $(PROJECT_ID) --format='value(projectNumber)')
INSTANCE_NAME := wordpress
INSTANCE_TYPE ?= db-f1-micro
REGION := us-west1
SERVICE_NAME := wordpress-service

VERSION := 1

INSTANCE_CONNECT_NAME := $(PROJECT_ID):$(REGION):$(INSTANCE_NAME)
SERVICE_ACCOUNT := $(SERVICE_NAME)@$(PROJECT_ID).iam.gserviceaccount.com

WORDPRESS_DB_HOST ?= 'localhost'
WORDPRESS_DB_SOCKET ?= /cloudsql/$(INSTANCE_CONNECT_NAME)
WORDPRESS_DB_USER ?= wordpress
WORDPRESS_DB_PASSWORD ?= $(shell cat /dev/urandom | LC_ALL=C tr -dc '[:alpha:]'| fold -w 30 | head -n1)
WORDPRESS_CONFIGURATION_SECRET := wordpress_configuration

.PHONY: init secrets

all:
	echo $(PROJECT_ID) $(PROJECTNUM)

secrets/wordpress.env:
	@echo "To create $@ file, run 'make env > $@'"

env: secrets/wordpress.env
	@echo export PROJECT_ID=$(PROJECT_ID)
	@echo export INSTANCE_CONNECT_NAME=$(INSTANCE_CONNECT_NAME)
	@echo export WORDPRESS_DB_HOST=$(WORDPRESS_DB_HOST)
	@echo export WORDPRESS_DB_USER=$(WORDPRESS_DB_USER)
	@echo export WORDPRESS_DB_PASSWORD=$(WORDPRESS_DB_PASSWORD)
	@echo export WORDPRESS_DB_SOCKET=$(WORDPRESS_DB_SOCKET)

init: secrets/wordpress.env
	@echo "# Run the following to initialize project"
	@echo gcloud config set project $(PROJECT_ID)
	@echo gcloud auth application-default login
	@echo gcloud iam service-accounts create $(SERVICE_NAME)
	@echo gcloud sql instances create $(INSTANCE_NAME) \
    --project $(PROJECT_ID) \
    --database-version MYSQL_8_0 \
    --tier $(INSTANCE_TYPE) \
    --region $(REGION)
	@echo gcloud sql databases create $(WORDPRESS_DB_HOST) \
    --instance $(INSTANCE_NAME)
	@echo gcloud sql users create $(WORDPRESS_DB_USER) \
    --instance $(INSTANCE_NAME) \
    --password $(WORDPRESS_DB_PASSWORD)

secrets:
	@echo gcloud secrets delete wordpress-db-password
	@echo echo -n $$WORDPRESS_DB_PASSWORD \| gcloud secrets create wordpress-db-password --data-file=-
	@echo echo -n $$WORDPRESS_DB_PASSWORD \| gcloud secrets versions add wordpress-db-password --data-file=-
	@echo
	@echo gcloud secrets delete wordpress-smtp-pass
	@echo echo -n $$WORDPRESS_SMTP_PASS \| gcloud secrets create wordpress-smtp-pass --data-file=-
	@echo echo -n $$WORDPRESS_SMTP_PASS \| gcloud secrets versions add wordpress-smtp-pass --data-file=-
	@echo

grants:
	gcloud secrets add-iam-policy-binding wordpress-db-password \
    --member serviceAccount:$(PROJECTNUM)-compute@developer.gserviceaccount.com \
    --role roles/secretmanager.secretAccessor
	gcloud secrets add-iam-policy-binding wordpress-db-password \
		--member serviceAccount:${SERVICE_ACCOUNT} \
    --role roles/secretmanager.secretAccessor
	## 
	gcloud projects add-iam-policy-binding $(PROJECT_ID) \
		--member serviceAccount:${SERVICE_ACCOUNT} \
		--role roles/run.invoker
	# Cloud SQL Client
	gcloud projects add-iam-policy-binding $(PROJECT_ID) \
		--member serviceAccount:${SERVICE_ACCOUNT} \
		--role roles/cloudsql.client
	gcloud projects add-iam-policy-binding  $(PROJECT_ID) \
		--member serviceAccount:${SERVICE_ACCOUNT} \
		--role='roles/storage.objectViewer'
	gcloud projects add-iam-policy-binding  $(PROJECT_ID) \
		--member serviceAccount:${SERVICE_ACCOUNT} \
		--role='roles/storage.objectCreator'
	# For viewing objects
	gcloud projects add-iam-policy-binding  $(PROJECT_ID) \
		--member serviceAccount:${SERVICE_ACCOUNT} \
		--role='roles/storage.objectViewer'
	# For creating objects
	gcloud projects add-iam-policy-binding  $(PROJECT_ID) \
		--member serviceAccount:${SERVICE_ACCOUNT} \
		--role='roles/storage.objectCreator'
	# For full control
	gcloud projects add-iam-policy-binding  $(PROJECT_ID) \
		--member serviceAccount:${SERVICE_ACCOUNT} \
		--role='roles/storage.objectAdmin'



IMAGE := gcr.io/$(PROJECT_ID)/wordpress
build: Dockerfile
	gcloud builds submit --tag $(IMAGE) .

push:
	docker tag local/wordpress:local gcr.io/$(PROJECT_ID)/wordpress:latest
	docker push gcr.io/$(PROJECT_ID)/wordpress:latest
	docker tag local/wordpress:local gcr.io/$(PROJECT_ID)/wordpress:$(VERSION)
	docker push gcr.io/$(PROJECT_ID)/wordpress:$(VERSION)

deploy:
	gcloud run deploy wordpress \
    --platform managed \
    --region $(REGION) \
    --image $(IMAGE) \
    --add-cloudsql-instances $(INSTANCE_CONNECT_NAME) \
		--service-account=$(SERVICE_ACCOUNT) \
		--env-vars-file=run.env \
    --allow-unauthenticated
		## --update-secrets=WORDPRESS_DB_PASSWORD=wordpress-db-password:latest \


delete_service:
	gcloud run services delete wordpress \
		--region $(REGION)

replace:
	gcloud run services replace service.yaml

clean:
	rm -rf local/cache{1,2}/*
	docker rmi local/wordpress:local
