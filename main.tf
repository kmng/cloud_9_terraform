provider "aws" {
  region = var.aws_region
}

resource "aws_vpc" "main_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name      = "VPC-${var.stack_name}"
    Terraform = "true"
  }
}



resource "aws_vpc_dhcp_options" "main_dhcp_options" {
  domain_name_servers = ["AmazonProvidedDNS"]
  domain_name         = "example.com"
}

# Associate DHCP option set with VPC
resource "aws_vpc_dhcp_options_association" "main_dhcp_association" {
  vpc_id          = aws_vpc.main_vpc.id
  dhcp_options_id = aws_vpc_dhcp_options.main_dhcp_options.id
}


resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.main_vpc.id
  tags = {
    Name      = "Internet-Gateway-${var.stack_name}"
    Terraform = "true"
  }
}


resource "aws_eip" "nat_eip" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.internet_gateway]
  tags = {
    Name      = "EIP-${var.stack_name}"
    Terraform = "true"
  }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public.id
  depends_on    = [aws_internet_gateway.internet_gateway]
  tags = {
    Name      = "Nat-Gateway-${var.stack_name}"
    Terraform = "true"
  }
}





resource "aws_subnet" "public" {
  vpc_id     = aws_vpc.main_vpc.id
  cidr_block = "10.0.1.0/24"

  availability_zone       = "us-west-2a"
  map_public_ip_on_launch = true

  tags = {
    Name      = "public-${var.stack_name}"
    Terraform = "true"
  }
}


resource "aws_subnet" "private" {
  vpc_id     = aws_vpc.main_vpc.id
  cidr_block = "10.0.2.0/24"

  availability_zone       = "us-west-2a"
  map_public_ip_on_launch = false

  tags = {
    Name      = "private-${var.stack_name}"
    Terraform = "true"
  }
}


resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main_vpc.id
  tags = {
    Name      = "public-route-table-${var.stack_name}"
    Terraform = "true"
  }
}


resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main_vpc.id
  tags = {
    Name      = "private-route-table-${var.stack_name}"
    Terraform = "true"
  }
}



resource "aws_route" "public_internet_gateway" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.internet_gateway.id
}



resource "aws_route" "private_nat_gateway" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat.id
}



resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}


resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}


resource "aws_vpc_endpoint" "s3_endpoint" {
  vpc_id       = aws_vpc.main_vpc.id
  service_name = "com.amazonaws.${data.aws_region.current.name}.s3"
  policy       = <<POLICY
{
  "Statement": [
    {
      "Action": "*",
      "Effect": "Allow",
      "Resource": "*",
      "Principal": "*"
    }
  ]
}
POLICY
}

resource "aws_vpc_endpoint_route_table_association" "s3_endpoint_association_private" {
  route_table_id  = aws_route_table.private.id
  vpc_endpoint_id = aws_vpc_endpoint.s3_endpoint.id
}

resource "aws_vpc_endpoint_route_table_association" "s3_endpoint_association_public" {
  route_table_id  = aws_route_table.public.id
  vpc_endpoint_id = aws_vpc_endpoint.s3_endpoint.id
}

data "aws_region" "current" {}

resource "aws_cloud9_environment_ec2" "cloud9_instance" {
  name                        = "cloud9_instance-${var.stack_name}"
  instance_type               = "t2.medium"
  automatic_stop_time_minutes = 30
  subnet_id                   = aws_subnet.public.id
  image_id                    = "amazonlinux-2-x86_64"
  connection_type             = "CONNECT_SSM"

  tags = {
    Terraform = "true"
  }
}

data "aws_instance" "cloud9_instance" {
  filter {
    name = "tag:aws:cloud9:environment"
    values = [
    aws_cloud9_environment_ec2.cloud9_instance.id]
  }
}

resource "aws_eip" "cloud9_eip" {
  instance = data.aws_instance.cloud9_instance.id
  domain   = "vpc"
}



data "aws_security_group" "cloud9_secgroup" {
  filter {
    name = "tag:aws:cloud9:environment"
    values = [

      aws_cloud9_environment_ec2.cloud9_instance.id
    ]
  }
}

resource "aws_security_group_rule" "tcp_8080" {
  type              = "ingress"
  from_port         = 8080
  to_port           = 8080
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = data.aws_security_group.cloud9_secgroup.id
}

resource "aws_dynamodb_table" "company_table" {
  name         = "company_table-${var.stack_name}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "name"
  attribute {
    name = "name"
    type = "S"
  }
  tags = {
    Terraform = "true"
  }
}

data "archive_file" "lambda_code" {
  type        = "zip"
  source_dir = "lambda-producer"
  output_path = "lambda-producer.zip"
}

resource "aws_iam_role" "lambda_producer_function" {
  name = "ProducerFunctionRole"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}


resource "aws_iam_role_policy_attachment" "basic" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_producer_function.name
}


resource "aws_iam_policy" "dynamodb_table_policy" {
  name        = "Dynamodb_Read_Policy"
  description = "Policy for scan Dynamodb Table"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action   = ["dynamodb:*"],
        Effect   = "Allow",
        Resource = ["*"]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "dynamodb_table_policy_attachment" {
  policy_arn = aws_iam_policy.dynamodb_table_policy.arn
  role       = aws_iam_role.lambda_producer_function.name
}


resource "aws_lambda_function" "lambda_producer_function" {
  filename      = "lambda-producer.zip"
  function_name = "LambdaProducerFunction"
  role          = aws_iam_role.lambda_producer_function.arn
  handler       = "index.handler"
  runtime = "nodejs14.x"
  environment {
    variables = {
      TABLE_NAME = "company_table-${var.stack_name}"
    }
  }
}