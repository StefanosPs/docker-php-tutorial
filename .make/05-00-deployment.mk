##@ [Deployment]

.PHONY: deploy
deploy: # Build all images and deploy them to GCP
	@printf "$(GREEN)Switching to 'local' environment$(NO_COLOR)\n"
	@make --no-print-directory make-init
	@printf "$(GREEN)Starting docker setup locally$(NO_COLOR)\n"
	@make --no-print-directory docker-compose-up
	@printf "$(GREEN)Verifying that there are no changes in the secrets$(NO_COLOR)\n"
	@make --no-print-directory gpg-init
	@make --no-print-directory deployment-guard-secret-changes
	@printf "$(GREEN)Verifying that there are no uncommitted changes in the codebase$(NO_COLOR)\n"
	@make --no-print-directory deployment-guard-uncommitted-changes
	@printf "$(GREEN)Initializing gcloud$(NO_COLOR)\n"
	@make --no-print-directory gcp-init
	@printf "$(GREEN)Switching to 'prod' environment$(NO_COLOR)\n"
	@make --no-print-directory make-init ENVS="ENV=prod TAG=latest"
	@printf "$(GREEN)Creating build information file$(NO_COLOR)\n"
	@make --no-print-directory deployment-create-build-info-file
	@printf "$(GREEN)Building docker images$(NO_COLOR)\n"
	@make --no-print-directory docker-compose-build
	@printf "$(GREEN)Pushing images to the registry$(NO_COLOR)\n"
	@make --no-print-directory docker-compose-push
	@printf "$(GREEN)Creating build information file$(NO_COLOR)\n"
	@make --no-print-directory deployment-create-service-ip-file
	@printf "$(GREEN)Creating the deployment archive$(NO_COLOR)\n"
	@make --no-print-directory deployment-create-tar
	@printf "$(GREEN)Copying the deployment archive to the VMs and run the deployment$(NO_COLOR)\n"
	@make --no-print-directory deployment-run-on-vms
	@printf "$(GREEN)Clearing deployment archive$(NO_COLOR)\n"
	@make --no-print-directory deployment-clear-tar
	@printf "$(GREEN)Switching to 'local' environment$(NO_COLOR)\n"
	@make --no-print-directory make-init

# directory on the VM that will contain the files to start the docker setup
CODEBASE_DIRECTORY=/tmp/codebase

IGNORE_SECRET_CHANGES?=

.PHONY: deployment-guard-secret-changes
deployment-guard-secret-changes: ## Check if there are any changes between the decrypted and encrypted secret files
	@if ( ! make secret-diff || [ "$$(make secret-diff | grep ^@@)" != "" ] ) && [ "$(IGNORE_SECRET_CHANGES)" == "" ] ; then \
        printf "Found changes in the secret files => $(RED)ABORTING$(NO_COLOR)\n\n"; \
        printf "Use with IGNORE_SECRET_CHANGES=true to ignore this warning\n\n"; \
        make secret-diff; \
        exit 1; \
    fi
	@echo "No changes in the secret files!"

IGNORE_UNCOMMITTED_CHANGES?=

.PHONY: deployment-guard-uncommitted-changes
deployment-guard-uncommitted-changes: ## Check if there are any git changes and abort if so. The check can be ignore by passing `IGNORE_UNCOMMITTED_CHANGES=true`
	@if [ "$$(git status -s)" != "" ] && [ "$(IGNORE_UNCOMMITTED_CHANGES)" == "" ] ; then \
        printf "Found uncommitted changes in git => $(RED)ABORTING$(NO_COLOR)\n\n"; \
        printf "Use with IGNORE_UNCOMMITTED_CHANGES=true to ignore this warning\n\n"; \
        git status -s; \
        exit 1; \
    fi
	@echo "No uncommitted changes found!"

# FYI: make converts all new lines in spaces when they are echo'd 
# @see https://stackoverflow.com/a/54068252/413531
# To execute a shell command via $(command), the $ has to be escaped with another $
#  ==> $$(command)
# @see https://stackoverflow.com/a/26564874/413531
.PHONY: deployment-create-build-info-file
deployment-create-build-info-file: ## Create a file containing version information about the codebase
	@echo "BUILD INFO" > ".build/build-info"
	@echo "==========" >> ".build/build-info"
	@echo "User  :" $$(whoami) >> ".build/build-info"
	@echo "Date  :" $$(date --rfc-3339=seconds) >> ".build/build-info"
	@echo "Branch:" $$(git branch --show-current) >> ".build/build-info"
	@echo "" >> ".build/build-info"
	@echo "Commit" >> ".build/build-info"
	@echo "------" >> ".build/build-info"
	@git log -1 --no-color >> ".build/build-info"

.PHONY: deployment-create-service-ip-file
deployment-create-service-ip-file: ## Create a file containing the IPs of all services
	@make -s gcp-get-ips > ".build/service-ips"
	@sed -i "s/\r//g" ".build/service-ips"

# create tar archive
#  tar -czvf archive.tar.gz ./source
#
# extract tar archive
#  tar -xzvf archive.tar.gz -C ./target
#
# @see https://www.cyberciti.biz/faq/how-to-create-tar-gz-file-in-linux-using-command-line/
# @see https://serverfault.com/a/330133
.PHONY: deployment-create-tar
deployment-create-tar:
	# create the build directory
	rm -rf .build/deployment
	mkdir -p .build/deployment
	# copy the necessary files
	cp -r .make .build/deployment/
	cp Makefile .build/deployment/
	cp .infrastructure/scripts/deploy.sh .build/deployment/
	# move the ip services file
	mv .build/service-ips .build/deployment/service-ips
	# create the archive
	tar -czvf .build/deployment.tar.gz -C .build/deployment/ ./

.PHONY: deployment-clear-tar
deployment-clear-tar:
	# clear the build directory
	rm -rf .build/deployment
	# remove the archive
	rm -rf .build/deployment.tar.gz

.PHONY: deployment-run-on-vms
deployment-run-on-vms: ## Run the deployment script on all VMs
	"$(MAKE)" -j --output-sync=target	deployment-run-on-vm-application \
 				 						deployment-run-on-vm-php-fpm \
 				 						deployment-run-on-vm-php-worker \
 				 						deployment-run-on-vm-nginx

# Note: The VM_NAME is the same as the DOCKER_SERVICE_NAME, e.g. "application"
.PHONY: deployment-run-on-vm
deployment-run-on-vm: ## Run the deployment script on the VM specified by VM_NAME
	"$(MAKE)" -s gcp-scp-command SOURCE=".build/deployment.tar.gz" DESTINATION="deployment.tar.gz"
	"$(MAKE)" -s gcp-ssh-command COMMAND="sudo rm -rf $(CODEBASE_DIRECTORY) && sudo mkdir -p $(CODEBASE_DIRECTORY) && sudo tar -xzvf deployment.tar.gz -C $(CODEBASE_DIRECTORY) && cd $(CODEBASE_DIRECTORY) && sudo bash deploy.sh $(VM_NAME)"

.PHONY: deployment-run-on-vm-application
deployment-run-on-vm-application: ## Provision all VMs
	"$(MAKE)" --no-print-directory deployment-run-on-vm VM_NAME=$(VM_NAME_APPLICATION)

.PHONY: deployment-run-on-vm-php-fpm
deployment-run-on-vm-php-fpm:
	"$(MAKE)" --no-print-directory deployment-run-on-vm VM_NAME=$(VM_NAME_PHP_FPM)

.PHONY: deployment-run-on-vm-php-worker 
deployment-run-on-vm-php-worker:
	"$(MAKE)" --no-print-directory deployment-run-on-vm VM_NAME=$(VM_NAME_PHP_WORKER)

.PHONY: deployment-run-on-vm-nginx
deployment-run-on-vm-nginx:
	"$(MAKE)" --no-print-directory deployment-run-on-vm VM_NAME=$(VM_NAME_NGINX)

.PHONY: deployment-setup-db-on-vm
deployment-setup-db-on-vm: ## Setup the application on the VM. CAUTION: The docker setup must be running!
	"$(MAKE)" -s gcp-docker-compose-exec VM_NAME="$(VM_NAME_APPLICATION)" DOCKER_SERVICE_NAME="$(DOCKER_SERVICE_NAME_APPLICATION)" DOCKER_COMMAND="php artisan app:setup-db"