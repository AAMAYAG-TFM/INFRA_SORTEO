
terraform { 
  required_providers {
    aws = "4.16.0"
  }
}
 
 provider "aws" {  
    access_key=var.access_key
    secret_key=var.secret_key
    region="us-east-2"
}

 #  ******* RECURSO DE LA RED VIRTUAL EN LA NUBE Y SUBREDES *******

# Inicio configuracion de VPC
resource "aws_vpc" "amag_vpc" {
  cidr_block       = "10.0.0.0/16"
  instance_tenancy = "default"
  enable_dns_hostnames = true
  tags = {
    Name = "vpc_amag"
  }
}

 # Inicio configuracion de Subredes:
# Nota: Requerido al menos dos zonas de disponibilidad y una subred por zona
resource "aws_subnet" "amag_subnet_web_1" {
  vpc_id     = aws_vpc.amag_vpc.id
  
  cidr_block = "10.0.2.0/24"
  availability_zone = "us-east-2a"
  tags = {
    Name = "amag_subnet_web_1"
  }
}

resource "aws_subnet" "amag_subnet_web_2" {
  vpc_id     = aws_vpc.amag_vpc.id
  
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-east-2b"
  tags = {
    Name = "amag_subnet_web_2"
  }
}


# Configuracion de las dos Instancias
#  ami = "ami-09aa052a03469eaa7" 
# -- Instancia No. 1 NGINX,  NODEJS Y CLIENTE MONGO
resource "aws_instance" "amag_instance_1_nginx" {
  ami = "ami-0004ed63c8664f098" 
  instance_type = "t2.micro"
  availability_zone=  "us-east-2a"
  subnet_id = aws_subnet.amag_subnet_web_1.id
  associate_public_ip_address = true
     tags = {
    Name = "amag_instance_1_nginx"
  }
  vpc_security_group_ids = [aws_security_group.amag_sg_nginx.id]
 
}

# -- Instancia No. 2 NGINX,  NODE y BD
#ami = "ami-06d1c4ab012eca730" 
resource "aws_instance" "amag_instance_2_nginx" {
   ami = "ami-086e82a5ee323fc4d" 
  instance_type = "t2.micro"
  availability_zone=  "us-east-2b"   
  associate_public_ip_address = true
  subnet_id = aws_subnet.amag_subnet_web_2.id
  vpc_security_group_ids = [aws_security_group.amag_sg_nginx.id]
  tags = {
    Name = "amag_instance_2_nginx"
  } 
}
 

 # ******* CONFIGURACION BALANCEADOR GRUPOS DE SEGURIDAD **********

 # Grupo de seguridad WEB
 resource "aws_security_group" "amag_sg_nginx" {
  name        = "amag_sg_nginx"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.amag_vpc.id
  
  ingress {
    protocol  = -1
    self      = true
    from_port = 0
    to_port   = 0
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "amag_sg_nginx"
  }
}

 

# Aplicacion de reglas al grupo de seguridad 
# Aplicacion de reglas al grupo de seguridad 
resource "aws_security_group_rule" "gsr2_controller-ssh" {
  security_group_id = aws_security_group.amag_sg_nginx.id
  type        = "ingress"
  protocol    = "tcp"
  from_port   = 22
  to_port     = 22
  cidr_blocks = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "gsr2_worker-https" {
  security_group_id =aws_security_group.amag_sg_nginx.id
  type        = "ingress"
  protocol    = "tcp"
  from_port   = 0
  to_port     = 27017
  cidr_blocks = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "gsr2_worker-http" {
  security_group_id =aws_security_group.amag_sg_nginx.id
  type        = "ingress"
  protocol    = "tcp"
  from_port   = 80
  to_port     = 80
  cidr_blocks = ["0.0.0.0/0"]
}


 #  ******* CONFIGURACION DE PUERTA DE ENLACE *******

# Esta puerta de enlace es requerida por el Balanceador de Carga
resource "aws_internet_gateway" "IGW" {
  vpc_id = aws_vpc.amag_vpc.id
  tags = {
    Name = "IGW"
  }
}

resource "aws_route_table" "amag_route_public" {
  vpc_id = aws_vpc.amag_vpc.id
 }
 
resource "aws_route_table_association" "amag_sn_route1" {
  subnet_id      = aws_subnet.amag_subnet_web_1.id
  route_table_id = aws_route_table.amag_route_public.id
}
 
 resource "aws_route_table_association" "amag_sn_route2" {
  subnet_id      = aws_subnet.amag_subnet_web_2.id
  route_table_id = aws_route_table.amag_route_public.id
}

resource "aws_route" "r" { 
  route_table_id = aws_route_table.amag_route_public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.IGW.id
}



 # ******* CONFIGURACION BALANCEADOR DE CARGA ***s*******
 resource "aws_lb" "amag_lb" {
  name = "loadbalanceamag"
  load_balancer_type = "application"  
  security_groups =  [aws_security_group.amag_sg_nginx.id]
  subnet_mapping {
    subnet_id = aws_subnet.amag_subnet_web_1.id
  }

   subnet_mapping {
    subnet_id = aws_subnet.amag_subnet_web_2.id
  }

  tags = {
    "Name" = "balanceador_carga_amag"
  }
}

resource "aws_lb_target_group" "amag_tg" { 
  name     = "amag-lb-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.amag_vpc.id
   health_check {
    port     = 80
    protocol = "HTTP"
  }
}

resource "aws_lb_target_group_attachment" "target_inst1" {
  target_group_arn = aws_lb_target_group.amag_tg.arn
  target_id  = aws_instance.amag_instance_1_nginx.id
}

resource "aws_lb_target_group_attachment" "target_ins2" {
  target_group_arn = aws_lb_target_group.amag_tg.arn
  target_id = aws_instance.amag_instance_2_nginx.id
}

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.amag_lb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    target_group_arn = aws_lb_target_group.amag_tg.arn
    type = "forward"
  }
}

resource "aws_lb_listener_rule" "amag_rule_listener" {
  listener_arn = aws_lb_listener.front_end.arn
  priority     = 100
  action {
    type = "forward"
    target_group_arn = aws_lb_target_group.amag_tg.arn
  }
   condition {
   
    host_header {
      values = ["*.us-east-2.compute.amazonaws.com"]
    }  
  }
}
 