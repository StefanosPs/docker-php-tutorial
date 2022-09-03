#!/usr/bin/env bash

# Fail immediately if any command fails
set -e

usage="Usage: setup-gcp.sh project_id"
[ -z "$1" ] &&  echo "No project_id given! $usage" && exit 1

GREEN="\033[0;32m"
RED="\033[0;31m"
NO_COLOR="\033[0m"

project_id=$1
master_service_account_key_location=./gcp-master-service-account-key.json
region=us-central1
router_name=default-router
nat_name=default-nat-gateway
vm_zone=us-central1-a
vm_names="php-fpm nginx application php-worker"
mysql_db_name=mysql-2
redis_db_name=redis
private_vpc_range_name="google-managed-services-vpc-allocation"
network="default"

printf "${GREEN}Setting up GCP project for${NO_COLOR}\n"
echo "==="
echo "project_id: ${project_id}"

printf "${GREEN}Activating master service account${NO_COLOR}\n"
gcloud auth activate-service-account --key-file="${master_service_account_key_location}" --project="${project_id}"

# -q / --quiet assumes defaults => commands can run unattended https://stackoverflow.com/a/35923207/413531

printf "${GREEN}Removing Instances${NO_COLOR}\n"
for vm_name in $vm_names; do
  printf "${GREEN}Service: ${vm_name} ${NO_COLOR}\n"
  gcloud compute instances delete ${vm_name} --zone="${vm_zone}" --delete-disks=all -q || printf "${RED}FAILED!${NO_COLOR}\n"
done;

printf "${GREEN}Removing NAT Gateway${NO_COLOR}\n"
gcloud compute routers nats delete "${nat_name}" --router="${router_name}" --router-region="${region}" -q || printf "${RED}FAILED!${NO_COLOR}\n"

printf "${GREEN}Removing Router${NO_COLOR}\n"
gcloud compute routers delete "${router_name}" --region="${region}" -q || printf "${RED}FAILED!${NO_COLOR}\n"

printf "${GREEN}Removing MySQL${NO_COLOR}\n"
gcloud sql instances delete "${mysql_db_name}" -q || printf "${RED}FAILED!${NO_COLOR}\n"

printf "${GREEN}Removing Redis${NO_COLOR}\n"
gcloud redis instances delete "${redis_db_name}" --region="${region}" -q || printf "${RED}FAILED!${NO_COLOR}\n"

printf "${GREEN}Removing VPC peering range allocation${NO_COLOR}\n"
gcloud compute addresses delete "${private_vpc_range_name}" --global -q || printf "${RED}FAILED!${NO_COLOR}\n"

printf "${GREEN}VPC peering for Google Services${NO_COLOR}\n"
gcloud services vpc-peerings delete --network="${network}" -q || printf "${RED}FAILED!${NO_COLOR}\n"
