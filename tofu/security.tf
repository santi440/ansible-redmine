resource "aws_security_group" "ec2" {
  name        = "${local.name}-ec2-sg"
  description = "Acceso SSH y HTTP a la instancia de Redmine"
  vpc_id      = aws_vpc.redmine.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_cidr_blocks
  }

  ingress {
    description = "HTTP de Redmine"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.http_cidr_blocks
  }

  egress {
    description = "Salida para descargas y actualizaciones"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name}-ec2-sg"
  }
}

resource "aws_security_group" "rds" {
  name        = "${local.name}-rds-sg"
  description = "Permite PostgreSQL solo desde la instancia de Redmine"
  vpc_id      = aws_vpc.redmine.id

  ingress {
    description     = "PostgreSQL desde EC2"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }

  tags = {
    Name = "${local.name}-rds-sg"
  }
}
