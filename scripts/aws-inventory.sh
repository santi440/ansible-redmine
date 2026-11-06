#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOFU_DIR="${ROOT_DIR}/tofu"
OUT_DIR="${ROOT_DIR}/inventory/aws"
OUT_FILE="${OUT_DIR}/hosts.yml"

if ! command -v tofu >/dev/null 2>&1; then
  echo "ERROR: OpenTofu no está instalado." >&2
  exit 1
fi

if ! tofu -chdir="${TOFU_DIR}" output -raw ec2_public_ip >/dev/null 2>&1; then
  echo "ERROR: no hay outputs de OpenTofu. Ejecutá primero 'tofu apply'." >&2
  exit 1
fi

ec2_ip="$(tofu -chdir="${TOFU_DIR}" output -raw ec2_public_ip)"
db_host="$(tofu -chdir="${TOFU_DIR}" output -raw rds_address)"
db_port="$(tofu -chdir="${TOFU_DIR}" output -raw rds_port)"
db_name="$(tofu -chdir="${TOFU_DIR}" output -raw rds_database_name)"
db_user="$(tofu -chdir="${TOFU_DIR}" output -raw rds_username)"
ssh_key="${SSH_PRIVATE_KEY_FILE:-$(tofu -chdir="${TOFU_DIR}" output -raw ssh_private_key_path)}"

mkdir -p "${OUT_DIR}"
umask 077
cat > "${OUT_FILE}" <<YAML
---
all:
  children:
    aws:
      hosts:
        redmine:
          ansible_host: "${ec2_ip}"
          ansible_user: "ubuntu"
          ansible_ssh_private_key_file: "${ssh_key}"
          ansible_python_interpreter: /usr/bin/python3
          redmine_host_name: "${ec2_ip}"
          redmine_db_host: "${db_host}"
          redmine_db_port: ${db_port}
          redmine_db_name: "${db_name}"
          redmine_db_user: "${db_user}"
          redmine_db_sslmode: "require"
          redmine_verify_local_postgresql: false
          redmine_db_password: "{{ lookup('env', 'TF_VAR_db_password') }}"
YAML
chmod 600 "${OUT_FILE}"

echo "Inventario generado: ${OUT_FILE}"
