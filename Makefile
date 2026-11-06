.PHONY: lint yamllint ansible-lint tofu-fmt tofu-validate shell lab-secret molecule up provision verify destroy

TOFU_DIR := tofu
LAB_SECRET_FILE := inventory/group_vars/all/vault.yml

lint: yamllint ansible-lint tofu-fmt shell

yamllint:
	yamllint .

ansible-lint:
	ansible-lint

tofu-fmt:
	tofu -chdir=$(TOFU_DIR) fmt -check -recursive

tofu-validate:
	tofu -chdir=$(TOFU_DIR) init -backend=false
	tofu -chdir=$(TOFU_DIR) validate

shell:
	bash -n scripts/*.sh

lab-secret:
	@command -v openssl >/dev/null || { echo "ERROR: openssl no está instalado."; exit 1; }
	@umask 077; \
	if [ -f "$(LAB_SECRET_FILE)" ]; then \
		echo "Ya existe $(LAB_SECRET_FILE)."; \
	else \
		mkdir -p "$(dir $(LAB_SECRET_FILE))"; \
		password="$$(openssl rand -hex 24)"; \
		printf '%s\n' '---' "vault_redmine_db_password: \"$${password}\"" > "$(LAB_SECRET_FILE)"; \
		echo "Generado $(LAB_SECRET_FILE) (ignorado por Git, modo 0600)."; \
	fi

molecule:
	molecule test

up: lab-secret
	vagrant up --provision

provision: lab-secret
	vagrant provision

verify:
	ansible-playbook playbooks/verify.yml

destroy:
	vagrant destroy -f
