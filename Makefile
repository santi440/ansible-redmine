.PHONY: lint yamllint ansible-lint lab-secret molecule up provision verify destroy

LAB_SECRET_FILE := inventory/group_vars/all/vault.yml

lint: yamllint ansible-lint

yamllint:
	yamllint .

ansible-lint:
	ansible-lint

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
