##@ [GCP]

.PHONY: gcp-init
gcp-init: validate-gcp-variables ## Initialize the `gcloud` cli and authenticate docker with the keyfile defined via GCP_DEPLOYMENT_SERVICE_ACCOUNT_KEY.
	@$(if $(GCP_DEPLOYMENT_SERVICE_ACCOUNT_KEY),,$(error "GCP_DEPLOYMENT_SERVICE_ACCOUNT_KEY is undefined"))
	@$(if $(GCP_PROJECT_ID),,$(error "GCP_PROJECT_ID is undefined"))
	gcloud auth activate-service-account --key-file="$(GCP_DEPLOYMENT_SERVICE_ACCOUNT_KEY)" --project="$(GCP_PROJECT_ID)"
	cat "$(GCP_DEPLOYMENT_SERVICE_ACCOUNT_KEY)" | docker login -u _json_key --password-stdin https://gcr.io

.PHONY: validate-gcp-variables
validate-gcp-variables:
	@$(if $(GCP_PROJECT_ID),,$(error "GCP_PROJECT_ID is undefined"))
	@$(if $(GCP_ZONE),,$(error "GCP_ZONE is undefined"))

# @see https://cloud.google.com/sdk/gcloud/reference/compute/ssh
.PHONY: gcp-ssh-command
gcp-ssh-command: validate-gcp-variables ## Run an arbitrary SSH command on the VM via IAP tunnel. Usage: `make gcp-ssh-command COMMAND="whoami"`
	@$(if $(VM_NAME),,$(error "VM_NAME is undefined"))
	@$(if $(COMMAND),,$(error "COMMAND is undefined"))
	gcloud compute ssh $(VM_NAME) --project $(GCP_PROJECT_ID) --zone $(GCP_ZONE) --tunnel-through-iap --command="$(COMMAND)"

.PHONY: gcp-ssh-login
gcp-ssh-login: validate-gcp-variables ## Log into a VM via IAP tunnel
	@$(if $(VM_NAME),,$(error "VM_NAME is undefined"))
	gcloud compute ssh $(VM_NAME) --project $(GCP_PROJECT_ID) --zone $(GCP_ZONE) --tunnel-through-iap

# @see https://cloud.google.com/sdk/gcloud/reference/compute/scp
.PHONY: gcp-scp-command
gcp-scp-command: validate-gcp-variables ## Copy a file via scp to the VM via IAP tunnel. Usage: `make gcp-scp-command SOURCE="foo" DESTINATION="bar"`
	@$(if $(VM_NAME),,$(error "VM_NAME is undefined"))
	@$(if $(SOURCE),,$(error "SOURCE is undefined"))
	@$(if $(DESTINATION),,$(error "DESTINATION is undefined"))
	gcloud compute scp $(SOURCE) $(VM_NAME):$(DESTINATION) --project $(GCP_PROJECT_ID) --zone $(GCP_ZONE) --tunnel-through-iap

# Defines the default secret version to retrieve from the Secret Manager
SECRET_VERSION?=latest

# @see https://cloud.google.com/sdk/gcloud/reference/secrets/versions/access
.PHONY: gcp-secret-get
gcp-secret-get: ## Retrieve and print the secret $(SECRET_NAME) in version $(SECRET_VERSION) from the Secret Manager
	@$(if $(SECRET_NAME),,$(error "SECRET_NAME is undefined"))
	@$(if $(SECRET_VERSION),,$(error "SECRET_VERSION is undefined"))
	@gcloud secrets versions access $(SECRET_VERSION) --secret=$(SECRET_NAME)

.PHONY: gcp-docker-compose-exec
gcp-docker-compose-exec: ## Run a command in a docker container vid compose on the VM. Usage: `make gcp-docker-compose-exec DOCKER_SERVICE_NAME="application" DOCKER_COMMAND="echo 'Hello world!'"`
	@$(if $(DOCKER_SERVICE_NAME),,$(error "DOCKER_SERVICE_NAME is undefined"))
	@$(if $(DOCKER_COMMAND),,$(error "DOCKER_COMMAND is undefined"))
	"$(MAKE)" -s gcp-ssh-command COMMAND="cd $(CODEBASE_DIRECTORY) && sudo make docker-compose-exec DOCKER_SERVICE_NAME='$(DOCKER_SERVICE_NAME)' DOCKER_COMMAND='$(DOCKER_COMMAND)'"

.PHONY: gcp-docker-exec
gcp-docker-exec: ## Run a command in a docker container on the VM. Usage: `make gcp-docker-exec DOCKER_SERVICE_NAME="application" DOCKER_COMMAND="echo 'Hello world!'"`
	@$(if $(DOCKER_SERVICE_NAME),,$(error "DOCKER_SERVICE_NAME is undefined"))
	@$(if $(DOCKER_COMMAND),,$(error "DOCKER_COMMAND is undefined"))
	"$(MAKE)" -s gcp-ssh-command COMMAND="cd $(CODEBASE_DIRECTORY) && sudo docker exec $(DOCKER_SERVICE_NAME) $(DOCKER_COMMAND)"

# Retrieve IPs 

.PHONY: gcp-get-ips
gcp-get-ips: ## Get the IP addresses for all services
	@printf "$(DOCKER_SERVICE_NAME_MYSQL):"
	@"$(MAKE)" -s gcp-get-private-ip-mysql
	@printf "$(DOCKER_SERVICE_NAME_REDIS):"
	@"$(MAKE)" -s gcp-get-private-ip-redis
	@for vm_name_service_name in $(ALL_VM_SERVICE_NAMES); do \
  		vm_name=`echo $$vm_name_service_name | cut -d ":" -f 1`; \
  		service_name=`echo $$vm_name_service_name | cut -d ":" -f 2`; \
  		printf "$$service_name:"; \
  		make -s gcp-get-private-ip-vm VM_NAME=$$vm_name; \
  	  done;

# @see https://cloud.google.com/compute/docs/instances/view-ip-address
.PHONY: gcp-get-public-ip-vm
gcp-get-public-ip-vm: ## Get the public ip of a VM
	@$(if $(GCP_PROJECT_ID),,$(error "GCP_PROJECT_ID is undefined"))
	@$(if $(VM_NAME),,$(error "VM_NAME is undefined"))
	gcloud compute instances list --filter="name~'$(VM_NAME)'" --format="get(EXTERNAL_IP)" --project=$(GCP_PROJECT_ID)

.PHONY: gcp-get-private-ip-vm
gcp-get-private-ip-vm: ## Get the private ip of a VM
	@$(if $(GCP_PROJECT_ID),,$(error "GCP_PROJECT_ID is undefined"))
	@$(if $(VM_NAME),,$(error "VM_NAME is undefined"))
	gcloud compute instances list --filter="name~'$(VM_NAME)'" --format="get(INTERNAL_IP)" --project=$(GCP_PROJECT_ID)

.PHONY: gcp-get-private-ip-nginx
gcp-get-private-ip-nginx: ## Get the private ip of nginx VM
	"$(MAKE)" gcp-get-private-ip-vm VM_NAME=$(VM_NAME_NGINX)

.PHONY: gcp-get-private-ip-mysql
gcp-get-private-ip-mysql: ## Get the private IP address of the SQL service
	gcloud sql instances describe $(VM_NAME_MYSQL) --format="get(ipAddresses[0].ipAddress)" --project=$(GCP_PROJECT_ID)

.PHONY: gcp-get-private-ip-redis
gcp-get-private-ip-redis: ## Get the private IP address of the Redis service
	gcloud redis instances describe $(VM_NAME_REDIS) --format="get(host)" --project=$(GCP_PROJECT_ID) --region=$(GCP_REGION)

# see https://cloud.google.com/memorystore/docs/redis/auth-overview#auth_behavior
# see https://cloud.google.com/memorystore/docs/redis/managing-auth#getting_the_auth_string
.PHONY: gcp-get-redis-auth
gcp-get-redis-auth: ## Get the AUTH string of the Redis service
	gcloud redis instances get-auth-string $(VM_NAME_REDIS) --project=$(GCP_PROJECT_ID) --region=$(GCP_REGION)

.PHONY: gcp-info-redis
gcp-info-redis: ## Show redis information
	gcloud redis instances list --project=$(GCP_PROJECT_ID) --region=$(GCP_REGION)

.PHONY: gcp-info-mysql
gcp-info-mysql: ## Show mysql information
	gcloud sql instances list --project=$(GCP_PROJECT_ID)

.PHONY: gcp-info-vms
gcp-info-vms: ## Show VM information
	gcloud compute instances list --project=$(GCP_PROJECT_ID)
