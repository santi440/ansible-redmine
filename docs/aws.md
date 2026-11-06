# Despliegue en AWS con OpenTofu

Esta variante mantiene la instalación de Redmine de la parte 1, pero cambia la
infraestructura:

- La **instancia EC2** la crea OpenTofu.
- **PostgreSQL no se instala con Ansible**: se usa **AWS RDS**.
- Todos los recursos de AWS se gestionan desde `tofu/`.
- El playbook `playbooks/aws.yml` ejecuta los roles de la aplicación, salvo
  `redmine_database`.

La instalación con Vagrant sigue funcionando sin cambios.

---

## 1. Arquitectura

```text
Host de trabajo
  │  OpenTofu aplica la infraestructura
  │  Ansible se conecta por SSH
  │
  ├── SSH 22 ───────────────────────────────┐
  └── HTTP 80 ──────────────────────────────┤
                                            ▼
┌──────────────────────── VPC 10.20.0.0/16 ────────────────────────┐
│                                                                  │
│  Subred pública 10.20.0.0/24     Subred pública 10.20.1.0/24     │
│  ┌────────────────────────┐                                      │
│  │ EC2 Ubuntu 24.04       │                                      │
│  │ Redmine + Puma + Nginx │                                      │
│  │ Elastic IP             │                                      │
│  └───────────┬────────────┘                                      │
│              │ 5432                                               │
│              ▼                                                    │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │ AWS RDS PostgreSQL 16                                      │  │
│  │ Subredes privadas 10.20.10.0/24 y 10.20.11.0/24             │  │
│  │ Sin acceso público                                         │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  Security Group EC2: 22 y 80 de entrada, salida libre            │
│  Security Group RDS: 5432 solo desde el Security Group de EC2    │
└──────────────────────────────────────────────────────────────────┘
```

---

## 2. Recursos gestionados por OpenTofu

Todo lo que se crea en AWS está declarado en `tofu/`:

| Archivo | Recursos |
| --- | --- |
| `network.tf` | VPC, Internet Gateway, dos subredes públicas, dos privadas y route tables |
| `security.tf` | Security Group de EC2 y Security Group de RDS |
| `compute.tf` | Key Pair, instancia EC2 y Elastic IP |
| `rds.tf` | DB Subnet Group y instancia RDS PostgreSQL |
| `locals.tf` | Tags comunes, zonas de disponibilidad y AMI de Ubuntu 24.04 |
| `outputs.tf` | IP pública, endpoint de RDS, URL y comando SSH |
| `variables.tf` | Región, red, instancia, base y credenciales |
| `providers.tf` | Provider de AWS y tags por defecto |

No se crean recursos de AWS desde Ansible. Ansible solo configura el sistema
operativo y la aplicación dentro de la EC2.

---

## 3. Requisitos

- OpenTofu 1.6 o superior.
- Credenciales de AWS disponibles para el provider (`AWS_PROFILE`,
  `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`, rol de instancia, etc.) con
  permisos para VPC, EC2, Key Pair, Elastic IP y RDS.
- Una clave SSH. Por defecto se usa `~/.ssh/id_ed25519` y
  `~/.ssh/id_ed25519.pub`.
- Ansible instalado en el host que ejecuta el playbook.
- Una contraseña de al menos 8 caracteres para RDS.

> **Costos:** EC2 y RDS generan costo mientras están encendidos. El laboratorio
> usa recursos pequeños, pero conviene destruirlos al terminar con
> `tofu -chdir=tofu destroy`.

---

## 4. Configuración

```bash
cd 05-IaC/integradora_p1

cp tofu/terraform.tfvars.example tofu/terraform.tfvars
$EDITOR tofu/terraform.tfvars

export TF_VAR_db_password='una-contraseña-larga'
```

`tofu/terraform.tfvars` está ignorado por Git. La contraseña **no** se escribe en
el repositorio: se pasa por la variable de entorno `TF_VAR_db_password`, que usan
tanto OpenTofu como el inventario de Ansible.

Variables importantes:

| Variable | Default | Descripción |
| --- | --- | --- |
| `aws_region` | `us-east-1` | Región de AWS |
| `project` | `redmine` | Prefijo de nombres y tags |
| `environment` | `lab` | Entorno del despliegue |
| `instance_type` | `t3.micro` | Tipo de EC2 |
| `db_instance_class` | `db.t3.micro` | Clase de RDS |
| `db_engine_version` | `16` | Versión mayor de PostgreSQL |
| `ssh_public_key_path` | `~/.ssh/id_ed25519.pub` | Clave pública para EC2 |
| `ssh_private_key_path` | `~/.ssh/id_ed25519` | Clave privada para Ansible |
| `ssh_cidr_blocks` | `0.0.0.0/0` | CIDR autorizados para SSH |
| `http_cidr_blocks` | `0.0.0.0/0` | CIDR autorizados para HTTP |

Se recomienda restringir `ssh_cidr_blocks` a la IP propia:

```hcl
ssh_cidr_blocks = ["203.0.113.10/32"]
```

---

## 5. Flujo de despliegue

### 5.1 Crear la infraestructura

```bash
tofu -chdir=tofu init
tofu -chdir=tofu validate
tofu -chdir=tofu plan
tofu -chdir=tofu apply
```

El flujo de AWS se ejecuta con comandos manuales; el único script es el que
genera el inventario, porque traduce los outputs de OpenTofu al formato de
Ansible.

### 5.2 Generar el inventario

El inventario se genera desde los outputs de OpenTofu:

```bash
./scripts/aws-inventory.sh
```

Escribe `inventory/aws/hosts.yml` (ignorado por Git) con:

- IP pública de la EC2.
- Usuario `ubuntu`.
- Ruta de la clave privada.
- Endpoint, puerto, base y usuario de RDS.
- `redmine_db_sslmode: require`.
- `redmine_verify_local_postgresql: false`, porque PostgreSQL no corre en la EC2.
- `redmine_db_password` tomada de `TF_VAR_db_password` con `lookup('env', ...)`.

La contraseña no queda escrita en el archivo.

### 5.3 Ejecutar Ansible

```bash
export TF_VAR_db_password='una-contraseña-larga'
ansible-playbook -i inventory/aws/hosts.yml playbooks/aws.yml
```

El playbook `playbooks/aws.yml`:

1. Espera a que la instancia acepte SSH y a que `cloud-init` termine.
2. Ejecuta `redmine_common`.
3. Ejecuta `redmine_ruby`.
4. Ejecuta `redmine`.
5. Ejecuta `redmine_nginx`.

No ejecuta `redmine_database` porque PostgreSQL ya existe en RDS.

### 5.4 Verificar

```bash
export TF_VAR_db_password='una-contraseña-larga'
ansible-playbook -i inventory/aws/hosts.yml playbooks/verify.yml
```

Las comprobaciones son las mismas que en Vagrant, pero la conexión a PostgreSQL
apunta a RDS y usa `sslmode=require`. La comprobación del servicio local de
PostgreSQL se omite con `redmine_verify_local_postgresql: false`, porque en AWS
la base es un servicio gestionado externo a la EC2.

### 5.5 Acceder

La URL se obtiene con:

```bash
tofu -chdir=tofu output -raw redmine_url
```

También se puede entrar por SSH con:

```bash
tofu -chdir=tofu output -raw ssh_command
```

### 5.6 Destruir

```bash
export TF_VAR_db_password='una-contraseña-larga'
tofu -chdir=tofu destroy
rm -f inventory/aws/hosts.yml
```

Destruye EC2, RDS, red y demás recursos, y elimina el inventario generado.

---

## 6. Qué cambia respecto de la instalación con Vagrant

| Tema | Vagrant | AWS |
| --- | --- | --- |
| Infraestructura | VirtualBox + Vagrant | OpenTofu |
| Base de datos | Rol `redmine_database` en la VM | RDS creado por OpenTofu |
| Playbook | `playbooks/site.yml` | `playbooks/aws.yml` |
| Roles de base | Se ejecuta `redmine_database` | No se ejecuta |
| Conexión a base | `127.0.0.1:5432` | Endpoint de RDS, `sslmode=require` |
| Acceso | `127.0.0.1:8080` | Elastic IP en puerto 80 |
| Sistema operativo | Box `mw-ubuntu-24.04` | AMI oficial de Ubuntu 24.04 |

La aplicación, Ruby, Puma y Nginx se configuran exactamente con los mismos roles.

---

## 7. Detalles de seguridad

- RDS está en subredes privadas y con `publicly_accessible = false`.
- El Security Group de RDS solo acepta el puerto 5432 desde el Security Group de
  EC2.
- La contraseña de RDS se pasa por `TF_VAR_db_password` y no se escribe en Git.
- El estado de OpenTofu contiene datos sensibles. No se versiona:
  `tofu/*.tfstate` está en `.gitignore`.
- Los volúmenes de EC2 y RDS se crean cifrados.
- La EC2 exige IMDSv2 (`http_tokens = "required"`).
- Se recomienda restringir `ssh_cidr_blocks`.

Para un entorno real conviene mover el estado a un backend remoto (por ejemplo,
S3 con bloqueo) y usar AWS Secrets Manager o Ansible Vault para la contraseña.

---

## 8. Linters y validación

```bash
make lint
```

Ejecuta:

```bash
yamllint .
ansible-lint
tofu -chdir=tofu fmt -check -recursive
```

Validación de OpenTofu:

```bash
make tofu-validate
```

Equivale a:

```bash
tofu -chdir=tofu init -backend=false
tofu -chdir=tofu validate
```

El workflow de GitHub Actions también ejecuta `tofu fmt`, `tofu init` y
`tofu validate`, además de `yamllint`, `ansible-lint` y `molecule test`.

---

## 9. Problemas frecuentes

| Síntoma | Causa probable | Solución |
| --- | --- | --- |
| `no such file` al aplicar | No existe la clave pública indicada | Ajustar `ssh_public_key_path` |
| Timeout de SSH | Security Group sin la IP propia | Ajustar `ssh_cidr_blocks` |
| `password authentication failed` | La contraseña de Ansible no coincide con RDS | Usar el mismo `TF_VAR_db_password` |
| RDS no resuelve desde EC2 | RDS todavía creándose o Security Group incorrecto | Esperar el estado `available` y revisar el SG |
| `python3-apt` no encontrado | `cloud-init` todavía no instaló paquetes | El playbook espera con `cloud-init status --wait` |
| `tofu` pide `db_password` al destruir | La variable no está definida | Exportar `TF_VAR_db_password` también al destruir |

---

## 10. Estructura nueva

```text
05-IaC/integradora_p1/
├── playbooks/
│   └── aws.yml              # instala Redmine sin el rol de base
├── tofu/
│   ├── versions.tf
│   ├── providers.tf
│   ├── locals.tf
│   ├── variables.tf
│   ├── network.tf
│   ├── security.tf
│   ├── compute.tf
│   ├── rds.tf
│   ├── outputs.tf
│   ├── terraform.tfvars.example
│   └── .terraform.lock.hcl
├── scripts/
│   └── aws-inventory.sh     # genera inventory/aws/hosts.yml
├── inventory/aws/
│   └── hosts.yml            # generado, ignorado por Git
└── docs/aws.md              # este documento
```
