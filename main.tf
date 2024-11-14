# Define o provedor da AWS e a região onde os recursos serão criados
provider "aws" {
  region = "sa-east-1" 
  access_key = var.aws_access_key  # Tipo de variavel definido no variables.tf e informado em terraform.tfvars
  secret_key = var.aws_secret_key  # Tipo de variavel definido no variables.tf e informado em terraform.tfvars
}


# Amazon CloudFront, S3 e Amazon Route 53

# Gera uma string aleatória que será anexada ao final do nome do bucket.
resource "random_string" "bucket_suffix" {
    length  = 6       # Define o comprimento do sufixo aleatório
    special = false   # Define se deve incluir caracteres especiais
    upper   = false   # Define se deve incluir letras maiúsculas
  }

    
# Cria um bucket S3 para armazenar os ativos estáticos do e-commerce
resource "aws_s3_bucket" "ecommerce_bucket" {
  bucket = format("ecommerce-static-assets-%s", random_string.bucket_suffix.result)  # Nome do bucket com um sufixo aleatório para garantir unicidade
}
    
# Define a política do bucket para permitir apenas acesso da distribuição CloudFront
 resource "aws_s3_bucket_policy" "ecommerce_bucket_policy" {
  bucket = aws_s3_bucket.ecommerce_bucket.id
    
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          AWS = "*"
        },
        Action = "s3:GetObject",
        Resource = "${aws_s3_bucket.ecommerce_bucket.arn}/*",
        Condition = {
          StringEquals = {
            "AWS:Referer" = aws_cloudfront_distribution.cdn.arn
          }
        }
      }
    ]
  })
 }
    
# Configura uma distribuição do CloudFront para servir os ativos do S3 de forma segura
resource "aws_cloudfront_origin_access_identity" "oai" {
  comment = "Access Identity for S3 bucket through CloudFront"
}

resource "aws_cloudfront_distribution" "cdn" {
  origin {
    domain_name = aws_s3_bucket.ecommerce_bucket.bucket_regional_domain_name  # Domínio do bucket como origem
    origin_id   = "S3-ecommerce"  # ID único para identificar a origem
    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.oai.cloudfront_access_identity_path  # Identidade de acesso à origem
    }
  }

  enabled = true  # Habilita a distribuição do CloudFront

  # Configura o comportamento de cache padrão do CloudFront
  default_cache_behavior {
    target_origin_id       = "S3-ecommerce"  # Referência à origem configurada acima
    viewer_protocol_policy = "redirect-to-https"  # Redireciona acessos HTTP para HTTPS
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]  # Métodos permitidos para acessar o conteúdo
    cached_methods         = ["GET", "HEAD"]  # Métodos que o CloudFront armazena em cache

    # Configurações adicionais de cache
    forwarded_values {
      query_string = false  # Define se o CloudFront deve incluir strings de consulta
      cookies {
        forward = "none"  # Especifica que nenhum cookie será encaminhado para a origem
      }
    }
  }

  # Configura restrições geográficas (por exemplo, acesso permitido de todas as regiões)
  restrictions {
    geo_restriction {
      restriction_type = "none"  # Permite o acesso de todos os locais
    }
  }

  # Configura um certificado SSL padrão do CloudFront para servir o conteúdo com HTTPS
  viewer_certificate {
    cloudfront_default_certificate = true  # Usa o certificado SSL padrão do CloudFront
  }
}
# Configura a identidade de acesso de origem (Origin Access Identity - OAI) para permitir que o CloudFront acesse o bucket privado no S3
 resource "aws_cloudfront_origin_access_identity" "oai" {
   comment = "Acesso de CloudFront ao bucket S3 para ecommerce"
 }
    

# Cria uma zona de hospedagem no Route 53 para gerenciar o domínio do site
resource "aws_route53_zone" "main" {
  name = "yourdomain.com"  # Substitua pelo domínio real
}

# Cria um registro DNS para apontar "www.yourdomain.com" para o CloudFront, permitindo acesso ao site pelo domínio customizado
resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.main.zone_id  # ID da zona Route 53
  name    = "www"  # Subdomínio para acessar o site (ex: www.yourdomain.com)
  type    = "A"  # Tipo de registro DNS para apontar o domínio ao CloudFront
  alias {
    name                   = aws_cloudfront_distribution.cdn.domain_name  # Domínio do CloudFront
    zone_id                = aws_cloudfront_distribution.cdn.hosted_zone_id  # Zona do CloudFront
    evaluate_target_health = false  # Não avalia a saúde do alvo
  }
}

# 2. Amazon Cognito

# Cria um User Pool no Amazon Cognito para gerenciar autenticação e registro de usuários no e-commerce
resource "aws_cognito_user_pool" "users" {
  name = "ecommerce_user_pool"  # Nome do User Pool
}

# Cria um App Client associado ao User Pool, que será usado para autenticação no front-end do e-commerce
resource "aws_cognito_user_pool_client" "app" {
  name         = "ecommerce_app_client"  # Nome do App Client
  user_pool_id = aws_cognito_user_pool.users.id  # ID do User Pool associado
}

# 3. API Gateway

# Cria uma API REST no API Gateway para servir como back-end do e-commerce
resource "aws_api_gateway_rest_api" "ecommerce_api" {
  name        = "Ecommerce API"  # Nome da API
  description = "API for eCommerce backend"  # Descrição da API
}

# Define um recurso (endpoint) dentro da API para gerenciar itens
resource "aws_api_gateway_resource" "items" {
  rest_api_id = aws_api_gateway_rest_api.ecommerce_api.id  # ID da API associada
  parent_id   = aws_api_gateway_rest_api.ecommerce_api.root_resource_id  # Recurso raiz da API
  path_part   = "items"  # Caminho do recurso (ex: /items)
}

# Configura um método HTTP GET para o recurso /items, permitindo a consulta de itens no e-commerce
resource "aws_api_gateway_method" "get_items" {
  rest_api_id   = aws_api_gateway_rest_api.ecommerce_api.id  # ID da API
  resource_id   = aws_api_gateway_resource.items.id  # ID do recurso /items
  http_method   = "GET"  # Método HTTP GET
  authorization = "NONE"  # Sem autenticação (alternativas: Cognito, IAM)
}

# 4. API Handler

# Cria uma função Lambda para manipular as requisições da API (backend serverless)
resource "aws_lambda_function" "api_handler" {
  function_name = "ecommerce_api_handler"  # Nome da função Lambda
  handler       = "index.handler"  # Caminho do handler no código
  runtime       = "nodejs14.x"  # Ambiente de execução (pode ser alterado para outros runtimes)
  role          = aws_iam_role.lambda_exec.arn  # Role IAM para permissões da função Lambda
  filename      = "lambda_function_payload.zip"  # Arquivo zip com o código da função
}

# 5. AWS SNS

# Cria um tópico SNS para enviar notificações sobre atualizações de pedidos (ex: e-mail, SMS)
resource "aws_sns_topic" "order_updates" {
  name = "order-updates"  # Nome do tópico SNS
}

# 6. AWS SES, AWS SQS e Lambda para Processador de Pagamento

# Configura o domínio para envio de e-mails com SES, usado para enviar notificações e emails transacionais
resource "aws_ses_domain_identity" "ecommerce" {
  domain = "yourdomain.com"  # Domínio autenticado para envio de e-mails
}

# Configura um endereço de e-mail autenticado para notificações (envio via SES)
resource "aws_ses_email_identity" "notification_email" {
  email = "notifications@yourdomain.com"  # E-mail autenticado para envio de notificações
}

# Cria uma fila SQS para processar pedidos, melhorando a escalabilidade e desacoplamento do sistema
resource "aws_sqs_queue" "order_queue" {
  name = "order_queue"  # Nome da fila de pedidos
}

# Cria uma fila SQS para processar pagamentos
resource "aws_sqs_queue" "payment_queue" {
  name = "payment_queue"  # Nome da fila de pagamentos
}

# Cria uma fila SQS para produtos
resource "aws_sqs_products" "products_queue" {
  name = "products_queue"  # Nome da fila de produtos
}

# Cria uma função Lambda para processar pagamentos (ex: integração com provedores de pagamento)
resource "aws_lambda_function" "payment_processor" {
  function_name = "payment_processor"  # Nome da função Lambda para pagamentos
  handler       = "payment.handler"  # Caminho do handler no código
  runtime       = "nodejs14.x"  # Ambiente de execução
  role          = aws_iam_role.lambda_exec.arn  # Role IAM para permissões da função
  filename      = "lambda_function_payload.zip"  # Arquivo zip com o código da função
}

# 7. Amazon DynamoDB

# Cria uma tabela DynamoDB para armazenar informações de clientes
resource "aws_dynamodb_table" "customers" {
  name         = "Customers"  # Nome da tabela
  hash_key     = "customerId"  # Chave primária da tabela (ID do cliente)
  attribute {
    name = "customerId"
    type = "S"  # Tipo da chave (String)
  }
  billing_mode = "PAY_PER_REQUEST"  # Modo de pagamento conforme uso
}

# Cria uma tabela DynamoDB para armazenar pedidos
resource "aws_dynamodb_table" "orders" {
  name         = "Orders"  # Nome da tabela
  hash_key     = "orderId"  # Chave primária da tabela (ID do pedido)
  attribute {
    name = "orderId"
    type = "S"  # Tipo da chave
  }
  billing_mode = "PAY_PER_REQUEST"
}

# Cria uma tabela DynamoDB para armazenar pagamentos
resource "aws_dynamodb_table" "payments" {
  name         = "Payments"  # Nome da tabela
  hash_key     = "paymentId"  # Chave primária (ID do pagamento)
  attribute {
    name = "paymentId"
    type = "S"
  }
  billing_mode = "PAY_PER_REQUEST"
}

# Cria uma tabela DynamoDB para armazenar produtos
resource "aws_dynamodb_table" "products" {
  name         = "Products"  # Nome da tabela
  hash_key     = "paymentId"  # Chave primária (ID do produto)
  attribute {
    name = "productsId"
    type = "S"
  }
  billing_mode = "PAY_PER_REQUEST"
}

# Roles e Permissões

# Cria uma role IAM para funções Lambda, com permissões básicas de execução
resource "aws_iam_role" "lambda_exec" {
  name = "lambda_exec_role"  # Nome da role IAM
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow",
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

# Anexa a política básica de execução do Lambda à role, permitindo acesso a logs no CloudWatch
resource "aws_iam_policy_attachment" "lambda_exec_policy" {
  name       = "lambda_exec_policy"  # Nome da política IAM
  roles      = [aws_iam_role.lambda_exec.name]  # Associa a política à role Lambda
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"  # Política básica para Lambda
}

# Saida de recursos criados por este Terraform.

# S3 Bucket Output
output "ecommerce_bucket_name" {
  value       = aws_s3_bucket.ecommerce_bucket.bucket
  description = "Nome do bucket S3 onde os ativos estáticos estão armazenados."
}

# CloudFront Distribution Output
output "cloudfront_distribution_id" {
  value       = aws_cloudfront_distribution.cdn.id
  description = "ID da distribuição do CloudFront para o conteúdo do bucket S3."
}

output "cloudfront_distribution_domain" {
  value       = aws_cloudfront_distribution.cdn.domain_name
  description = "URL de domínio da distribuição CloudFront."
}

# Route 53 Zone Output
output "route53_zone_id" {
  value       = aws_route53_zone.main.zone_id
  description = "ID da zona hospedada do Route 53."
}

# Route 53 Record Output
output "route53_record_www" {
  value       = aws_route53_record.www.name
  description = "Nome do registro 'www' no Route 53 apontando para o CloudFront."
}

# Cognito User Pool Output
output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.users.id
  description = "ID do User Pool do Cognito para gerenciamento de usuários."
}

# Cognito User Pool Client Output
output "cognito_user_pool_client_id" {
  value       = aws_cognito_user_pool_client.app.id
  description = "ID do cliente do User Pool do Cognito."
}

# API Gateway Output
output "api_gateway_id" {
  value       = aws_api_gateway_rest_api.ecommerce_api.id
  description = "ID da API Gateway do e-commerce."
}

# API Gateway Resource Output
output "api_gateway_resource_id" {
  value       = aws_api_gateway_resource.items.id
  description = "ID do recurso 'items' na API Gateway."
}

# Lambda Function Outputs
output "lambda_api_handler_arn" {
  value       = aws_lambda_function.api_handler.arn
  description = "ARN da função Lambda que atua como handler da API."
}

output "lambda_payment_processor_arn" {
  value       = aws_lambda_function.payment_processor.arn
  description = "ARN da função Lambda que atua como processador de pagamentos."
}

# SNS Topic Output
output "sns_topic_order_updates_arn" {
  value       = aws_sns_topic.order_updates.arn
  description = "ARN do tópico SNS para atualizações de pedidos."
}

# SES Domain Identity Output
output "ses_domain_identity_arn" {
  value       = aws_ses_domain_identity.ecommerce.arn
  description = "ARN da identidade de domínio do SES."
}

# SES Email Identity Output
output "ses_email_identity_email" {
  value       = aws_ses_email_identity.notification_email.email
  description = "Email registrado para envio de notificações via SES."
}

# SQS Queue Outputs
output "sqs_order_queue_url" {
  value       = aws_sqs_queue.order_queue.id
  description = "URL da fila SQS para pedidos."
}

output "sqs_payment_queue_url" {
  value       = aws_sqs_queue.payment_queue.id
  description = "URL da fila SQS para pagamentos."
}

output "sqs_products_queue_url" {
  value       = aws_sqs_products.products_queue.id
  description = "URL da fila SQS para produtos."
}

# DynamoDB Table Outputs
output "dynamodb_customers_table_name" {
  value       = aws_dynamodb_table.customers.name
  description = "Nome da tabela DynamoDB para armazenar informações dos clientes."
}

output "dynamodb_orders_table_name" {
  value       = aws_dynamodb_table.orders.name
  description = "Nome da tabela DynamoDB para armazenar informações dos pedidos."
}

output "dynamodb_payments_table_name" {
  value       = aws_dynamodb_table.payments.name
  description = "Nome da tabela DynamoDB para armazenar informações dos pagamentos."
}

output "dynamodb_products_table_name" {
  value       = aws_dynamodb_table.products.name
  description = "Nome da tabela DynamoDB para armazenar informações dos produtos."
}

# IAM Role Output
output "lambda_exec_role_arn" {
  value       = aws_iam_role.lambda_exec.arn
  description = "ARN do papel IAM associado às funções Lambda."
}

