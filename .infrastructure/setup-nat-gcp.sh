#!/usr/bin/env bash

# Fail immediately if any command fails
set -e

usage="Usage: setup-gcp.sh project_id"
[ -z "$1" ] &&  echo "No project_id given! $usage" && exit 1

GREEN="\033[0;32m"
NO_COLOR="\033[0m"

project_id=$1
region=us-central1
router_name=default-router
nat_name=default-nat-gateway
master_service_account_key_location=./gcp-master-service-account-key.json
network="default"

printf "${GREEN}Setting up GCP project for${NO_COLOR}\n"
echo "==="
echo "project_id: ${project_id}"

printf "${GREEN}Activating master service account${NO_COLOR}\n"
gcloud auth activate-service-account --key-file="${master_service_account_key_location}" --project="${project_id}"

printf "${GREEN}Creating Router${NO_COLOR}\n"
gcloud compute routers create "${router_name}" \
      --region="${region}" \
      --network="${network}"

printf "${GREEN}Creating NAT Gateway${NO_COLOR}\n"
gcloud compute routers nats create "${nat_name}"  \
    --router="${router_name}" \
    --router-region="${region}" \
    --auto-allocate-nat-external-ips \
    --nat-all-subnet-ip-ranges \
    --enable-logging \
    --network="${network}"
