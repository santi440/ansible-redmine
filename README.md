# Redmine 7.0.3 con Ansible sobre Vagrant

Instalación reproducible de **Redmine 7.0.3** (última versión estable al momento
de la entrega) en Ubuntu 24.04 usando **Ansible**. Todo el aprovisionamiento se
ejecuta dentro de una VM creada con Vagrant; el código de Redmine queda en
`/opt/redmine` y la aplicación corre con el usuario `redmine`, nunca como root.

| Requisito | Implementación |
| --- | --- |
| Ruby del SO reemplazada por una instalada aparte | **Ruby 4.0.9** compilada con **rbenv** en `/home/redmine/.rbenv`. No se instala el paquete `ruby` del sistema. |
| Usuario distinto de root | Usuario y grupo `redmine`; Puma y sus workers corren con `User=redmine` en systemd. |
| Application server + web server con estáticos fuera de Ruby | **Puma** escucha en un socket UNIX y **Nginx** actúa como proxy inverso. Nginx sirve `/assets`, `/help` y los archivos estáticos desde disco. |
| Base de datos soportada, local y migrable | **PostgreSQL 16** en `127.0.0.1:5432`, con base y rol propios. La conexión está parametrizada para poder mover la base a otro host. |
| La VM reinicia y el servicio sigue funcionando | `postgresql`, `redmine` y `nginx` quedan `enabled`. Puma tiene `Restart=always`. |

## Arquitectura

```text
Host
  │  127.0.0.1:8080 → VM:80
  ▼
┌──────────────────────── VM Ubuntu 24.04 ────────────────────────┐
│                                                                 │
│  Nginx :80                                                      │
│    ├── /assets/*, /help/* ──► disco (/opt/redmine/public)       │
│    └── resto ── socket UNIX ──► Puma (usuario redmine)          │
│                                      │                          │
│                                      ▼                          │
│                              PostgreSQL 16                      │
│                              127.0.0.1:5432                     │
└─────────────────────────────────────────────────────────────────┘
```

Redmine se instala en **`/opt/redmine`**. El home del usuario `redmine`
(`/home/redmine`) solo contiene el toolchain de Ruby (`rbenv`).

## Estructura

```text
integradora_p1/
├── Vagrantfile
├── ansible.cfg
├── requirements.yml
├── Makefile
├── inventory/
│   ├── hosts.yml
│   └── group_vars/all/
│       ├── main.yml
│       └── vault.yml.example
├── playbooks/
│   ├── site.yml
│   └── verify.yml
├── roles/
│   ├── redmine_common/      # paquetes, locale, usuario y /opt/redmine
│   ├── redmine_database/    # PostgreSQL local, rol, base y pg_hba
│   ├── redmine_ruby/        # rbenv, ruby-build, Ruby y bundler
│   ├── redmine/             # descarga, configuración, Puma y systemd
│   └── redmine_nginx/       # proxy inverso y estáticos
├── informes/                # informe de la parte 1 (Markdown y PDF)
├── molecule/default/        # pruebas de integración con Docker + systemd
└── .github/workflows/ci.yml
```

## Puesta en marcha

La box utilizada por defecto es `mw-ubuntu-24.04` (la construida con Packer en
la actividad anterior). Si se usa otra box, se puede indicar por entorno:

```bash
REDMINE_BOX=ubuntu-noble64-local REDMINE_SSH_USER=vagrant vagrant up --provision
```

Uso normal:

```bash
vagrant up --provision
```

Si los puertos por defecto ya están ocupados (por ejemplo, por otra VM), se
pueden elegir otros:

```bash
REDMINE_SSH_PORT=2223 REDMINE_HTTP_PORT=8081 vagrant up --provision
```

En ese caso la web queda en <http://127.0.0.1:8081>.

Vagrant ejecuta el provisionador `ansible_local`: instala Ansible dentro de la
VM, instala las colecciones de `requirements.yml` y corre
`playbooks/site.yml` en modo local con `become`.

Acceso:

| | |
| --- | --- |
| Web | <http://127.0.0.1:8080> |
| SSH | `vagrant ssh` |
| Usuario inicial de Redmine | `admin` / `admin` |

Redmine obliga a cambiar la contraseña en el primer ingreso.

### Ejecución manual dentro de la VM

```bash
vagrant ssh
cd /vagrant
ansible-galaxy collection install -r requirements.yml
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --become
ansible-playbook -i inventory/hosts.yml playbooks/verify.yml --become
```

## Variables principales

Están en `inventory/group_vars/all/main.yml`:

| Variable | Valor por defecto | Descripción |
| --- | --- | --- |
| `redmine_version` | `7.0.3` | Versión estable de Redmine. |
| `redmine_ruby_version` | `4.0.9` | Última Ruby soportada por Redmine 7.0 (serie 4.0). |
| `redmine_user` / `redmine_group` | `redmine` | Usuario de la aplicación. |
| `redmine_root` | `/opt/redmine` | Directorio de instalación de Redmine. |
| `redmine_host_name` | `127.0.0.1:8080` | Host usado por Redmine en URLs absolutas. |
| `redmine_db_name` / `redmine_db_user` | `redmine` | Base y rol de PostgreSQL. |
| `redmine_db_password` | `Redmine_2026!` | Se puede sobreescribir con `vault_redmine_db_password`. |
| `redmine_db_host` / `redmine_db_port` | `127.0.0.1` / `5432` | Conexión de la aplicación a la base. |
| `redmine_db_allowed_cidrs` | loopback | Redes autorizadas en `pg_hba.conf`. |
| `redmine_puma_workers` | `2` | Workers de Puma. |
| `redmine_puma_threads` | `5` | Hilos por worker. |
| `redmine_http_port` | `80` | Puerto de Nginx dentro de la VM. |

Para usar una contraseña fuera del repositorio:

```bash
cp inventory/group_vars/all/vault.yml.example inventory/group_vars/all/vault.yml
$EDITOR inventory/group_vars/all/vault.yml
ansible-vault encrypt inventory/group_vars/all/vault.yml
```

## Cómo se cumple cada punto

### Ruby instalada fuera del sistema operativo

`roles/redmine_ruby` clona `rbenv` y `ruby-build` en el home del usuario
`redmine`, compila Ruby 4.0.9 y fija esa versión como global. No se instala el
paquete `ruby` de Ubuntu. La unidad systemd usa `rbenv exec` con
`RBENV_ROOT=/home/redmine/.rbenv`.

Comprobación:

```bash
sudo -u redmine -H bash -lc \
  'export RBENV_ROOT=/home/redmine/.rbenv; export PATH=$RBENV_ROOT/bin:$RBENV_ROOT/shims:$PATH; ruby -v'
command -v ruby || echo "Ruby del sistema no instalada"
```

### Usuario no root

El usuario `redmine` es un usuario de sistema con home propio. La unidad
`/etc/systemd/system/redmine.service` declara `User=redmine` y `Group=redmine`.
El playbook de verificación comprueba que los procesos de Puma pertenezcan a ese
usuario.

### Puma detrás de Nginx, estáticos servidos por Nginx

`config/puma.rb` solo declara:

```ruby
bind "unix:///opt/redmine/tmp/puma.sock"
```

No se abre ningún puerto TCP para la aplicación. Nginx recibe el tráfico en el
puerto 80 y:

- sirve `/assets/*` con `alias /opt/redmine/public/assets/`;
- sirve `/help/*`, favicon, robots.txt y páginas de error desde disco;
- envía el resto de las peticiones a Puma por el socket UNIX.

Además, `roles/redmine` activa explícitamente en
`config/environments/production.rb` la línea:

```ruby
config.public_file_server.enabled = ENV['RAILS_SERVE_STATIC_FILES'].present?
```

Sin `RAILS_SERVE_STATIC_FILES`, Rails deja de servir `/public` por su cuenta y el
reparto queda garantizado. La verificación consulta el mismo asset directamente
a Puma y espera un `404`, es decir, Ruby no puede servir estáticos.

### PostgreSQL local y preparado para moverse

`roles/redmine_database` instala PostgreSQL, escucha solo en `localhost`, crea el
rol y la base, y configura `scram-sha-256` para conexiones TCP locales.

Para mover la base a otro servidor:

1. Exportar la base actual:

   ```bash
   sudo -u postgres pg_dump -Fc redmine > /tmp/redmine.dump
   ```

2. Restaurarla en el servidor destino con `pg_restore`.
3. Ajustar en el inventario `redmine_db_host` (y `redmine_db_port` si cambia).
4. Agregar la IP del host de Redmine a `redmine_db_allowed_cidrs` en el servidor
   de base de datos.
5. Copiar `/opt/redmine/files` si se migran los adjuntos.

No hay cambios de código involucrados: la conexión se genera desde
`config/database.yml.j2`.

### Reinicio de la VM

Los tres servicios quedan habilitados:

```bash
vagrant ssh -c 'systemctl is-active postgresql nginx redmine'
vagrant ssh -c 'systemctl is-enabled postgresql nginx redmine'
vagrant reload
```

Después del reinicio, Redmine vuelve a responder en <http://127.0.0.1:8080>.
Puma tiene `Restart=always` y Nginx arranca después de `redmine.service` por el
drop-in `/etc/systemd/system/nginx.service.d/redmine-order.conf`.

## Verificación

```bash
ansible-playbook playbooks/verify.yml
```

El playbook de verificación comprueba:

- servicios `redmine`, `nginx` y `postgresql` activos;
- procesos de Redmine ejecutados por `redmine`;
- versión de Ruby de rbenv;
- conexión a PostgreSQL;
- respuesta HTTP 200 de Redmine;
- asset CSS precompilado servido por Nginx;
- respuesta `404` al pedir ese asset directamente a Puma por el socket.

Comandos útiles:

```bash
curl -I http://127.0.0.1:8080/
curl -I http://127.0.0.1:8080/assets/application-<hash>.css
sudo systemctl status redmine nginx postgresql
sudo journalctl -u redmine -n 100 --no-pager
sudo tail -f /opt/redmine/log/production.log
sudo tail -f /var/log/nginx/redmine_error.log
```

## Estado verificado en el laboratorio

Comprobado el 2026-11-06 sobre la box `mw-ubuntu-24.04`:

| Comprobación | Resultado |
| --- | --- |
| `ruby -v` con rbenv | `ruby 4.0.9` |
| Ruby del sistema | No instalada |
| Puma | `8.0.2`, procesos del usuario `redmine` |
| Nginx | `1.24.0 (Ubuntu)`, sirviendo `/assets` |
| PostgreSQL | 16, activo y habilitado |
| `playbooks/verify.yml` | `ok=21`, `failed=0` |
| Segunda ejecución de `site.yml` | `ok=60`, `changed=0` |
| `vagrant reload` + HTTP | Servicios activos y HTTP 200 |
| `yamllint` / `ansible-lint` | Sin errores (0 fallos, 0 warnings) |
| `molecule test` | RC=0; idempotencia y verify correctos |

## Linters y pruebas

```bash
make lint           # yamllint + ansible-lint
make molecule       # molecule test
make verify         # playbook de verificación contra la VM
```

Molecule levanta un contenedor Ubuntu 24.04 con systemd, ejecuta los cinco roles
y corre las mismas verificaciones que `playbooks/verify.yml`. El workflow de
GitHub Actions ejecuta `yamllint`, `ansible-lint` y `molecule test`.

## Informes

- [Parte 1 — Redmine con Vagrant y Ansible](informes/parte-1-vagrant-ansible.pdf)

La fuente Markdown del informe está en `informes/`.

## Notas de operación

- **Versión de Redmine:** 7.0.3 es la última estable disponible en
  <https://www.redmine.org/releases/>. El checksum SHA256 se descarga y valida
  antes de descomprimir.
- **Versión de Ruby:** Redmine 7.0 soporta Ruby 3.2 a 4.0 y recomienda 4.0.4 o
  superior. Se usa 4.0.9.
- **Assets:** si se cambia de versión de Redmine o se fuerza una reinstalación,
  ejecutar con `-e redmine_recompile_assets=true` para volver a precompilar.
- **Box:** `mw-ubuntu-24.04` ya trae el usuario `ubuntu`, sudo sin contraseña,
  claves de Vagrant y guest additions para el directorio `/vagrant`.
- **Puerto en URLs:** Nginx reenvía `Host` y deduce `X-Forwarded-Port` del mismo
  para conservar el `8080` del host en las redirecciones.
