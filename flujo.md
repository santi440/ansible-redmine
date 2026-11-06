# Flujo de la integradora — 05 IaC

Este documento explica **solo lo nuevo** respecto de la integradora de `04-web`.
La arquitectura de Redmine, rbenv, Puma, Nginx, los estáticos y PostgreSQL local
ya están explicados allí y no se repiten.

Lo que cambia acá es la capa de automatización: se pasa de scripts de shell a
**Ansible declarativo**, con roles, variables, verificación, pruebas y CI.

---

## 1. Qué cambia respecto de `04-web`

| Antes (`04-web/integradora`) | Ahora (`05-IaC/integradora_p1`) |
| --- | --- |
| Tres scripts `provision/*.sh` | Cinco roles de Ansible |
| Provision imperativo, sin idempotencia formal | Tareas declarativas e idempotentes |
| Valores fijos en los scripts | Variables en inventario + Vault opcional |
| Verificación manual con `demo.sh` | Playbook `verify.yml` reutilizable |
| Sin pruebas automatizadas | Molecule con Docker + systemd |
| Sin linters ni CI | `yamllint`, `ansible-lint` y GitHub Actions |
| Redmine 7.0.2 / Ruby 4.0.7 | Redmine 7.0.3 / Ruby 4.0.9 |
| Aplicación en `/var/www/redmine` | Aplicación en `/opt/redmine` |
| Box preparada a mano en el mismo proyecto | Se reutiliza la box `mw-ubuntu-24.04` de la actividad de Packer |

Este documento se enfoca en esos puntos nuevos.

---

## 2. Flujo completo de ejecución

```
Host
 │
 │  vagrant up --provision
 ▼
Vagrantfile
 ├── crea/enciende la VM
 ├── reenvía 127.0.0.1:8080 → VM:80
 └── ejecuta el provisionador ansible_local
          │
          ▼
     ansible_local
     ├── instala Ansible dentro de la VM
     ├── ansible-galaxy collection install -r requirements.yml
     └── ansible-playbook playbooks/site.yml --become
                │
                ▼
        inventory/hosts.yml  (conexión local)
                │
                ▼
        playbooks/site.yml
                │
        ┌───────┴────────┬─────────────┬──────────┬─────────────┐
        ▼                ▼             ▼          ▼             ▼
 redmine_common   redmine_database  redmine_ruby  redmine   redmine_nginx
        │                │             │          │             │
        └────────────────┴─────────────┴──────────┴─────────────┘
                                   │
                                   ▼
                         playbooks/verify.yml
                         (comprobaciones reales)
```

El orden de roles no es casual:

1. `redmine_common`: sistema, paquetes y usuario.
2. `redmine_database`: PostgreSQL listo antes de migrar.
3. `redmine_ruby`: Ruby listo antes de instalar gemas.
4. `redmine`: descarga, configura, migra, precompila y arranca Puma.
5. `redmine_nginx`: publica la aplicación cuando Puma ya existe.

---

## 3. Recorrido por roles (solo lo nuevo)

### `redmine_common`

Aporta la base declarativa:

- `ansible.builtin.assert` para validar Ubuntu 24.04 o superior.
- `ansible.builtin.apt` con la lista `redmine_common_packages`.
- `ansible.builtin.user` y `group` para el usuario de sistema `redmine`.
- `community.general.locale_gen` y `timezone`.
- `ansible.builtin.file` para `/opt/redmine`.

Novedad concreta: se agregó el paquete **`acl`**. Sin él, Ansible no puede
preparar archivos temporales para `become_user: postgres` en la box de Vagrant y
falla con un error de `chmod` sobre ACLs.

### `redmine_database`

Reemplaza el `CREATE ROLE`/`createdb` manual por módulos:

- `community.postgresql.postgresql_user` crea el rol con `LOGIN,NOINHERIT`.
- `community.postgresql.postgresql_db` crea la base con `owner` y `UTF8`.
- `template` genera `pg_hba.conf` con las CIDR permitidas.
- `lineinfile` ajusta `listen_addresses` y `port`.
- `meta: flush_handlers` fuerza el reinicio de PostgreSQL **antes** de crear el
  rol y la base. Sin eso, la configuración nueva podía no estar aplicada.
- La versión de PostgreSQL se detecta leyendo `/etc/postgresql`, no se hardcodea.

### `redmine_ruby`

La compilación sigue siendo la misma idea, pero ahora es idempotente:

- `ansible.builtin.git` con `update: false` para rbenv y ruby-build.
- `blockinfile` agrega el bloque de rbenv al `.bashrc` una sola vez.
- `rbenv install` usa `creates` para no recompilar si Ruby ya existe.
- `TMPDIR=/var/tmp` porque en Molecule `/tmp` es `noexec`.
- `rbenv rehash` y la comprobación de versión usan `changed_when: false`.

### `redmine`

Se divide en archivos para que el flujo sea legible:

| Archivo | Responsabilidad |
| --- | --- |
| `download.yml` | Descarga, valida checksum y descomprime |
| `configure.yml` | Bundler, `database.yml`, `Gemfile.local`, Puma y directorios |
| `database.yml` | Gemas, token, migraciones, datos por defecto y `host_name` |
| `assets.yml` | Precompila solo si hace falta |
| `service.yml` | Unidad systemd y espera del socket |

Novedades de idempotencia y robustez:

- La descarga usa `checksum` SHA256 y ya **no** usa `force: true`.
- `unarchive` usa `creates: Gemfile` para no descomprimir dos veces.
- `bundle check` decide si hace falta `bundle install`.
- `secret_token.rb` se genera solo si no existe (`stat`).
- `db:migrate` se marca con `changed_when: false`.
- Los datos por defecto se cargan solo si la consulta de “no data” da `0`.
  La consulta replica `Redmine::DefaultData::Loader.no_data?`:
  roles no builtin + trackers + estados + enumeraciones + consultas.
- `host_name` se ajusta con `rails runner` inline y `changed_when: false`,
  sin escribir ni borrar scripts temporales.
- `assets:precompile` corre solo si `public/assets` está vacío o si se fuerza
  con `-e redmine_recompile_assets=true`.
- `wait_for` espera el socket de Puma antes de que Nginx arranque.

### `redmine_nginx`

La configuración es la misma idea de proxy inverso, pero ahora:

- Se genera desde `redmine.conf.j2`.
- Se valida con el handler `nginx -t`.
- Se recarga solo si hubo cambios.
- Se instala un drop-in de systemd para que Nginx arranque después de Redmine.
- El sitio `default` se elimina de forma declarativa.

---

## 4. Idempotencia: mecanismos usados

| Tarea | Mecanismo |
| --- | --- |
| Descarga de Redmine | `checksum` sin `force` |
| Descompresión | `creates: Gemfile` |
| rbenv / ruby-build | `update: false` |
| Compilación de Ruby | `creates: .../bin/ruby` |
| Bundler | `creates: .../bin/bundle` |
| Gemas | `bundle check` + `when` |
| Token de sesión | `stat` + `when` |
| Datos por defecto | consulta `no_data?` + `when` |
| `host_name` | `changed_when: false` |
| Assets | `find` + `when` |
| Servicios | `state: started`, `enabled: true` |
| Configuración | `template` / `lineinfile` + handlers |
| Base de datos | módulos `postgresql_*` con `state: present` |

Resultado comprobado: un segundo `vagrant provision` termina con `changed=0`.

---

## 5. Verificación automatizada

`playbooks/verify.yml` importa `roles/redmine/tasks/verify.yml`. Las
comprobaciones nuevas respecto de la demo manual son:

- `service_facts` + `assert` para `redmine` y `nginx`.
- Búsqueda de cualquier servicio que empiece con `postgresql`.
  En Ubuntu conviven `postgresql.service` y `postgresql@16-main.service`.
- `pgrep -u redmine -f '[p]uma'` para confirmar el usuario de Puma.
- `pgrep -u root -f '[p]uma'` para confirmar que root no lo ejecuta.
- Versión de Ruby vía rbenv.
- `SELECT 1` contra PostgreSQL.
- HTTP 200 y contenido de Redmine.
- Asset CSS precompilado.
- Asset servido por Nginx (`Server: nginx`, sin `X-Runtime`).
- Asset pedido directo a Puma por socket: debe dar `404`.

Importante: por el inventario con `ansible_connection: local`, el verify se
ejecuta **dentro de la VM**:

```bash
vagrant ssh
cd /vagrant
ansible-playbook -i inventory/hosts.yml playbooks/verify.yml --become
```

---

## 6. Molecule

Flujo del escenario `default`:

```
create → converge → idempotence → verify → destroy
```

Configuración nueva:

- Driver Docker.
- Imagen `geerlingguy/docker-ubuntu2404-ansible`.
- Contenedor privilegiado con systemd y `cgroupns_mode: host`.
- Solo `tmpfs` en `/run`; se quitó `/tmp` porque era `noexec` y rompía Ruby.
- `converge.yml` usa rutas absolutas de roles con
  `MOLECULE_PROJECT_DIRECTORY`.
- `verify.yml` reutiliza las tareas del rol `redmine`.
- `requirements.yml` declara las colecciones del escenario; el paso
  `dependency` de Molecule las instala antes del `converge`.
- `collections.yml` queda como referencia para instalar las colecciones en
  forma manual.
- `destroy.yml` no hace nada: Molecule elimina el contenedor.

---

## 7. Linters y CI

### `yamllint`

- Extiende `default`.
- Desactiva límite de línea y `truthy`.
- Excluye `.ansible/`, `.cache/`, `.git/`, `.venv/` y `molecule/`.

### `ansible-lint`

- Perfil `production`.
- Omite `var-naming[no-role-prefix]` porque varios roles comparten el prefijo
  `redmine_`.
- Excluye rutas generadas y `molecule/`.

### `Makefile`

```bash
make lint       # yamllint + ansible-lint
make molecule   # molecule test
make up         # vagrant up --provision
make provision  # vagrant provision
make verify     # ansible-playbook playbooks/verify.yml
make destroy    # vagrant destroy -f
```

`make verify` también debe ejecutarse dentro de la VM, por el inventario local.

### GitHub Actions

Dos jobs:

1. `lint`: instala Ansible, colecciones, `yamllint`, `ansible-lint` y OpenTofu;
   ejecuta `yamllint`, `ansible-lint`, `tofu fmt -check`, `tofu init` y
   `tofu validate`.
2. `molecule`: depende de `lint`, instala Molecule con Docker y ejecuta
   `molecule test`.

---

## 8. Problemas nuevos y su solución

| Problema | Causa | Solución |
| --- | --- | --- |
| `chmod: invalid mode: 'A+user:postgres:rx:allow'` | Faltaba `acl` en la box de Vagrant | Agregar `acl` a los paquetes base |
| Ruby no compila en Molecule | `/tmp` montado `noexec` | Quitar `/tmp` del `tmpfs` y usar `TMPDIR=/var/tmp` |
| `load_default_data` no se ejecuta | `settings` ya tenía filas por migraciones | Consultar roles/trackers/estados/enumeraciones/queries |
| PostgreSQL figura como detenido | El servicio real es `postgresql@16-main` | Buscar cualquier servicio `^postgresql` |
| No se detectan procesos Puma | El proceso se llama `ruby`, no `puma` | Usar `pgrep -u redmine -f '[p]uma'` |
| `host_name` no era idempotente | Script temporal que siempre cambiaba | `rails runner` inline + `changed_when: false` |
| La descarga siempre cambiaba | `force: true` | Quitarlo y confiar en el checksum |
| La base se creaba antes de aplicar configuración | Handlers al final del play | `meta: flush_handlers` antes de crear rol/base |
| Nginx podía arrancar antes que Puma | Sin orden de systemd | Drop-in `After/Wants=redmine.service` |

---

## 9. Comandos de uso

```bash
# Aprovisionar desde cero
vagrant up --provision

# Reaplicar y comprobar idempotencia
vagrant provision

# Linters
make lint

# Pruebas de integración
make molecule

# Verificación dentro de la VM
vagrant ssh -c 'cd /vagrant && ansible-playbook -i inventory/hosts.yml playbooks/verify.yml --become'

# Apagar
vagrant halt
```

Acceso web: <http://127.0.0.1:8080> con `admin` / `admin`.

---

## 10. Estado final comprobado (2026-11-06)

- `yamllint`: OK.
- `ansible-lint`: 0 fallos, 0 warnings, perfil production.
- `tofu fmt -check -recursive tofu`: OK.
- `tofu validate`: configuración válida.
- `molecule test`: RC=0; converge `ok=60`, idempotencia `ok=60 changed=0`,
  verify `ok=21 failed=0` y destroy correcto.
- `playbooks/site.yml` dentro de la VM: `ok=60`, `failed=0`.
- Segunda ejecución consecutiva de `site.yml`: `changed=0`.
- `verify.yml`: `ok=21`, `failed=0`.
- `vagrant reload`: servicios activos y habilitados, HTTP 200.
- La variante AWS quedó validada estáticamente con `tofu fmt` y `tofu validate`;
  no se dejaron recursos activos para evitar costos.

---

## 11. Variante AWS con OpenTofu

Se agrega una segunda forma de ejecutar la misma aplicación, sin reemplazar el
flujo Vagrant:

```text
OpenTofu
  ├── VPC, subredes públicas y privadas
  ├── Security Groups
  ├── Key Pair + EC2 Ubuntu 24.04
  ├── Elastic IP
  └── RDS PostgreSQL 16 privada
        │
        └── 5432 solo desde el Security Group de EC2

Ansible
  └── playbooks/aws.yml
      ├── redmine_common
      ├── redmine_ruby
      ├── redmine
      └── redmine_nginx
```

Cambios concretos:

- Se agrega `tofu/` con todos los recursos de AWS declarados.
- Se agrega `playbooks/aws.yml`, que no ejecuta `redmine_database` porque la base
  ya existe en RDS.
- El rol `redmine` admite `redmine_db_sslmode`; para RDS se usa `require`.
- `redmine_verify_local_postgresql: false` evita que `verify.yml` exija un
  servicio PostgreSQL local en la EC2.
- `roles/redmine/templates/database.yml.j2` agrega `sslmode` solo cuando la
  variable tiene valor, para no romper Vagrant ni Molecule.
- Los módulos `community.postgresql` reciben `ssl_mode` con `omit` cuando la
  variable está vacía.
- `scripts/aws-inventory.sh` genera `inventory/aws/hosts.yml` desde los outputs
  de OpenTofu. Es el único script de AWS: el resto del flujo se ejecuta con
  comandos de OpenTofu y Ansible.
- La contraseña de RDS se pasa por `TF_VAR_db_password`; el inventario la lee
  con `lookup('env', ...)` y no la escribe en disco.
- El workflow de CI valida el formato y la configuración de OpenTofu.

Comandos:

```bash
cp tofu/terraform.tfvars.example tofu/terraform.tfvars
export TF_VAR_db_password='una-contraseña-larga'

tofu -chdir=tofu init
tofu -chdir=tofu apply

./scripts/aws-inventory.sh
ansible-playbook -i inventory/aws/hosts.yml playbooks/aws.yml
ansible-playbook -i inventory/aws/hosts.yml playbooks/verify.yml

tofu -chdir=tofu destroy
rm -f inventory/aws/hosts.yml
```

La guía completa está en [`docs/aws.md`](docs/aws.md).
