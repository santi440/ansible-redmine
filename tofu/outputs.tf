output "ec2_instance_id" {
  description = "ID de la instancia EC2 de Redmine."
  value       = aws_instance.redmine.id
}

output "ec2_public_ip" {
  description = "IP pública elástica de la instancia EC2."
  value       = aws_eip.redmine.public_ip
}

output "redmine_url" {
  description = "URL de acceso a Redmine."
  value       = "http://${aws_eip.redmine.public_ip}/"
}

output "ssh_command" {
  description = "Comando SSH para entrar a la instancia."
  value       = "ssh -i ${pathexpand(var.ssh_private_key_path)} ubuntu@${aws_eip.redmine.public_ip}"
}

output "ssh_private_key_path" {
  description = "Ruta de la clave privada usada para el inventario de Ansible."
  value       = pathexpand(var.ssh_private_key_path)
}

output "rds_address" {
  description = "Host de RDS para configurar Redmine."
  value       = aws_db_instance.redmine.address
}

output "rds_port" {
  description = "Puerto de RDS."
  value       = aws_db_instance.redmine.port
}

output "rds_endpoint" {
  description = "Endpoint completo de RDS."
  value       = aws_db_instance.redmine.endpoint
}

output "rds_database_name" {
  description = "Nombre de la base de datos de RDS."
  value       = aws_db_instance.redmine.db_name
}

output "rds_username" {
  description = "Usuario maestro de RDS."
  value       = aws_db_instance.redmine.username
}
