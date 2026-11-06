variable "aws_region" {
  description = "Región de AWS donde se crean los recursos."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Nombre del proyecto usado en los tags y nombres de recursos."
  type        = string
  default     = "redmine"
}

variable "environment" {
  description = "Entorno lógico del despliegue."
  type        = string
  default     = "lab"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "El entorno solo puede contener minúsculas, números y guiones."
  }
}

variable "vpc_cidr" {
  description = "Bloque CIDR de la VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Dos CIDR para las subredes públicas (EC2)."
  type        = list(string)
  default     = ["10.20.0.0/24", "10.20.1.0/24"]

  validation {
    condition     = length(var.public_subnet_cidrs) == 2
    error_message = "Se requieren exactamente dos subredes públicas."
  }
}

variable "private_subnet_cidrs" {
  description = "Dos CIDR para las subredes privadas (RDS)."
  type        = list(string)
  default     = ["10.20.10.0/24", "10.20.11.0/24"]

  validation {
    condition     = length(var.private_subnet_cidrs) == 2
    error_message = "Se requieren exactamente dos subredes privadas."
  }
}

variable "ssh_public_key_path" {
  description = "Ruta a la clave pública SSH que se usará para EC2."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "ssh_private_key_path" {
  description = "Ruta a la clave privada SSH correspondiente."
  type        = string
  default     = "~/.ssh/id_ed25519"
}

variable "ssh_cidr_blocks" {
  description = "CIDR autorizados para SSH. Restringirlo a la IP propia."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "http_cidr_blocks" {
  description = "CIDR autorizados para HTTP (Redmine)."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "instance_type" {
  description = "Tipo de instancia EC2."
  type        = string
  default     = "t3.micro"
}

variable "root_volume_size" {
  description = "Tamaño en GB del disco raíz de la EC2."
  type        = number
  default     = 30
}

variable "db_instance_class" {
  description = "Clase de instancia RDS."
  type        = string
  default     = "db.t3.micro"
}

variable "db_engine_version" {
  description = "Versión mayor de PostgreSQL en RDS."
  type        = string
  default     = "16"
}

variable "db_name" {
  description = "Nombre de la base de datos inicial de RDS."
  type        = string
  default     = "redmine"
}

variable "db_username" {
  description = "Usuario maestro de RDS."
  type        = string
  default     = "redmine"
}

variable "db_password" {
  description = "Contraseña del usuario maestro de RDS. Usar TF_VAR_db_password."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_password) >= 8
    error_message = "La contraseña de RDS debe tener al menos 8 caracteres."
  }
}

variable "db_allocated_storage" {
  description = "Almacenamiento inicial de RDS en GB."
  type        = number
  default     = 20
}

variable "db_max_allocated_storage" {
  description = "Límite de autoescalado de almacenamiento de RDS en GB."
  type        = number
  default     = 100
}

variable "db_backup_retention_period" {
  description = "Días de retención de backups de RDS. 0 desactiva los backups."
  type        = number
  default     = 0
}

variable "db_skip_final_snapshot" {
  description = "Evita el snapshot final al destruir RDS (útil en laboratorios)."
  type        = bool
  default     = true
}

variable "db_deletion_protection" {
  description = "Activa la protección contra borrado de RDS."
  type        = bool
  default     = false
}
