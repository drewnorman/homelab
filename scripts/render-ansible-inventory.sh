#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

mkdir -p ansible/inventory
tofu -chdir=terraform output -raw ansible_inventory > ansible/inventory/hosts.ini
printf 'Wrote ansible/inventory/hosts.ini\n'
