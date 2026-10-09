#!/usr/bin/env bash
# Phase 2 driver - run from WSL (Ubuntu), inside the Linux filesystem (~/).
#
# One-time setup
#   ./scripts/run.sh deps         install Ansible collections (amazon.aws)
#   ./scripts/run.sh bootstrap    S3 bucket for Terraform state + backend.hcl
#   ./scripts/run.sh vault-init   vault password file + encrypted vault.yml
#
# Daily flow (Steps 1-8)
#   ./scripts/run.sh image        Step 1    build + push Docker image
#   ./scripts/run.sh plan         Steps 2-3 terraform plan  (review!)
#   ./scripts/run.sh apply        Steps 2-3 terraform apply (saved plan)
#   ./scripts/run.sh fetch-key    SSH key from Secrets Manager -> ~/.ssh
#   ./scripts/run.sh configure    Steps 4-7 ansible-playbook site.yml
#   ./scripts/run.sh test         curl the app through the NLB
#   ./scripts/run.sh status       debug playbook (incl. etcd encryption proof)
#   ./scripts/run.sh destroy      Step 8    terraform destroy
#
# ENV=dev by default; ENV=prod ./scripts/run.sh plan  for another environment.
set -euo pipefail

ENV="${ENV:-dev}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF_BOOT="${ROOT}/terraform/bootstrap"
TF_LIVE="${ROOT}/terraform/live/${ENV}"
ANS="${ROOT}/ansible"
APP="${ROOT}/../app"
IMAGE="${IMAGE:-a1abhinavsingh/python-sample-app-demo:v2}"
VAULT_PASS="${HOME}/.ansible/vault/k8s-ha-${ENV}.pass"
VAULT_FILE="${ANS}/inventories/${ENV}/group_vars/all/vault.yml"
KEY_FILE="${HOME}/.ssh/k8s-ha-${ENV}.pem"
APP_HOST="foo.bar.com"

step() { echo -e "\n\033[36m==> $*\033[0m"; }
die()  { echo -e "\033[31mERROR: $*\033[0m" >&2; exit 1; }

check_fs() {
  [[ "${ROOT}" == /mnt/* ]] && die "Project is on a Windows drive (${ROOT}). Copy it to ~/ first (see README)."
  return 0
}

deps() {
  step "Ansible collections -> ${ANS}/collections"
  cd "${ANS}"
  ansible-galaxy collection install -r requirements.yml -p ./collections
  python3 -c "import boto3" 2>/dev/null || echo "NOTE: boto3 missing for Ansible. Run: pipx inject ansible boto3 botocore"
}

bootstrap() {
  step "Remote state bucket (bootstrap stack, local state)"
  terraform -chdir="${TF_BOOT}" init
  terraform -chdir="${TF_BOOT}" apply
  terraform -chdir="${TF_BOOT}" output -raw backend_hcl_dev \
    | sed "s#dev/terraform.tfstate#${ENV}/terraform.tfstate#" > "${TF_LIVE}/backend.hcl"
  echo "Wrote ${TF_LIVE}/backend.hcl:"; cat "${TF_LIVE}/backend.hcl"
}

vault_init() {
  step "Vault password file ${VAULT_PASS}"
  mkdir -p "$(dirname "${VAULT_PASS}")"; chmod 700 "$(dirname "${VAULT_PASS}")"
  if [[ ! -f "${VAULT_PASS}" ]]; then
    openssl rand -base64 32 > "${VAULT_PASS}"
    chmod 600 "${VAULT_PASS}"
    echo "Created. BACK IT UP in a password manager - without it vault.yml cannot be decrypted."
  else
    echo "Exists, keeping it."
  fi

  step "Encrypted secrets ${VAULT_FILE}"
  if [[ -f "${VAULT_FILE}" ]]; then
    echo "Exists, keeping it. Edit with: ansible-vault edit ${VAULT_FILE}"
    return
  fi
  local django etcd
  django="$(python3 -c 'import secrets; print(secrets.token_urlsafe(50))')"
  etcd="$(head -c 32 /dev/urandom | base64)"
  # Plaintext goes through a pipe only - never written to disk.
  cd "${ANS}"
  printf -- '---\nvault_django_secret_key: "%s"\nvault_etcd_encryption_key: "%s"\nvault_registry_username: ""\nvault_registry_password: ""\n' \
    "${django}" "${etcd}" \
    | ansible-vault encrypt --encrypt-vault-id "${ENV}" --output "${VAULT_FILE}"
  echo "Done. Check:  head -1 ${VAULT_FILE}   (must start with \$ANSIBLE_VAULT)"
}

image() {
  step "Step 1 - build and push ${IMAGE}"
  docker build -t "${IMAGE}" "${APP}"
  docker push "${IMAGE}"
}

tf_init() {
  [[ -f "${TF_LIVE}/backend.hcl" ]] || die "No backend.hcl - run: ./scripts/run.sh bootstrap"
  terraform -chdir="${TF_LIVE}" init -backend-config=backend.hcl -input=false > /dev/null
}

plan() {
  step "Steps 2-3 - terraform plan (${ENV})"
  tf_init
  terraform -chdir="${TF_LIVE}" fmt -check -recursive ../../ || echo "(fmt: run terraform fmt -recursive)"
  terraform -chdir="${TF_LIVE}" validate
  terraform -chdir="${TF_LIVE}" plan -out=tfplan
}

apply() {
  [[ -f "${TF_LIVE}/tfplan" ]] || plan
  step "Steps 2-3 - terraform apply (the saved, reviewed plan)"
  terraform -chdir="${TF_LIVE}" apply tfplan
  rm -f "${TF_LIVE}/tfplan"
  terraform -chdir="${TF_LIVE}" output
}

fetch_key() {
  step "SSH private key from AWS Secrets Manager -> ${KEY_FILE}"
  tf_init
  local secret region
  secret="$(terraform -chdir="${TF_LIVE}" output -raw ssh_key_secret_name)"
  region="$(grep -E '^region' "${TF_LIVE}/terraform.tfvars" | cut -d'"' -f2)"
  mkdir -p "${HOME}/.ssh"; chmod 700 "${HOME}/.ssh"
  umask 077
  aws secretsmanager get-secret-value --region "${region}" --secret-id "${secret}" \
    --query SecretString --output text > "${KEY_FILE}"
  chmod 600 "${KEY_FILE}"
  echo "Saved (mode 600)."
}

configure() {
  check_fs
  [[ -f "${KEY_FILE}" ]] || fetch_key
  [[ -f "${VAULT_FILE}" ]] || die "No vault.yml - run: ./scripts/run.sh vault-init"
  cd "${ANS}"
  step "Inventory discovered from EC2 tags"
  ansible-inventory --graph
  step "Steps 4-7 - ansible-playbook site.yml"
  ansible-playbook site.yml
  echo; echo "kubectl from WSL:  export KUBECONFIG=${ANS}/kubeconfig-${ENV}"
  test_app
}

test_app() {
  tf_init
  local dns code
  dns="$(terraform -chdir="${TF_LIVE}" output -raw nlb_dns)"
  step "Testing http://${dns}/demo/ (Host: ${APP_HOST})"
  for i in $(seq 1 18); do
    code=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: ${APP_HOST}" "http://${dns}/demo/" || true)
    echo "  attempt ${i}: HTTP ${code}"
    [[ "${code}" == "200" ]] && break
    sleep 10
  done
  echo
  echo "Browser - in an Administrator PowerShell on Windows:"
  echo "  Add-Content C:\\Windows\\System32\\drivers\\etc\\hosts \"\`n$(getent hosts "${dns}" | awk 'NR==1{print $1}') ${APP_HOST}\""
  echo "Then open http://${APP_HOST}/demo/"
}

status() {
  cd "${ANS}"
  ansible-playbook playbooks/90-debug.yml
}

destroy() {
  step "Step 8 - terraform destroy (${ENV})"
  tf_init
  terraform -chdir="${TF_LIVE}" destroy
  rm -f "${KEY_FILE}" "${ANS}/kubeconfig-${ENV}"
  echo "Kept: state bucket (bootstrap), vault password + vault.yml (reused next time)."
  echo "Remove the '${APP_HOST}' line from the Windows hosts file."
}

case "${1:-}" in
  deps)       deps ;;
  bootstrap)  bootstrap ;;
  vault-init) vault_init ;;
  image)      image ;;
  plan)       plan ;;
  apply)      apply ;;
  fetch-key)  fetch_key ;;
  configure)  configure ;;
  test)       test_app ;;
  status)     status ;;
  destroy)    destroy ;;
  *) grep -E '^#   ' "$0" | sed 's/^#   //'; exit 1 ;;
esac
