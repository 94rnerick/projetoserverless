# Define o provedor da AWS e a região onde os recursos serão criados
provider "aws" {
  region = "us-east-1"  # Altere para a região desejada, ex: "us-west-2" para Oregon
  access_key = var.aws_access_key  # Tipo de variavel definido no variables.tf e informado em terraform.tfvars
  secret_key = var.aws_secret_key  # Tipo de variavel definido no variables.tf e informado em terraform.tfvars
}

# Cria um bucket no S3 para armazenar o site
resource "aws_s3_bucket" "site_bucket" {
  bucket = "meu-bucket-de-site"  # Nome do bucket; deve ser único globalmente
  acl    = "public-read"         # Define o bucket como publicamente acessível para leitura

  # Configuração de hospedagem de site estático no S3
  website {
    index_document = "index.html"  # Define o arquivo padrão do site
    error_document = "error.html"  # Define a página de erro padrão
  }
}

# Define uma política de acesso público para o bucket S3, permitindo que qualquer usuário possa ler os objetos do bucket
resource "aws_s3_bucket_policy" "site_bucket_policy" {
  bucket = aws_s3_bucket.site_bucket.id  # Associa a política ao bucket criado acima

  policy = jsonencode({  # Converte a política para o formato JSON
    Version = "2012-10-17",  # Versão da política; deve ser esta para compatibilidade com AWS
    Statement = [
      {
        Sid       = "PublicReadGetObject",  # Identificador da política; pode ser qualquer valor único
        Effect    = "Allow",  # Define a política como permissiva
        Principal = "*",  # Permite acesso a qualquer usuário
        Action    = "s3:GetObject",  # Especifica que a ação permitida é a leitura dos objetos
        Resource  = "${aws_s3_bucket.site_bucket.arn}/*"  # Aplica a política a todos os objetos dentro do bucket
      }
    ]
  })
}

# Carrega os arquivos do site na pasta `site_files` e os envia para o bucket S3
resource "aws_s3_bucket_object" "site_files" {
  for_each = fileset("site_files", "**")  # Seleciona todos os arquivos dentro da pasta `site_files`
  bucket   = aws_s3_bucket.site_bucket.bucket  # Bucket onde os arquivos serão enviados
  key      = each.value  # Define o nome do arquivo no bucket
  source   = "site_files/${each.value}"  # Caminho local do arquivo a ser enviado
  acl      = "public-read"  # Define o arquivo como publicamente acessível

  # Alternativas:
  # - Poderia usar `object_lock_configuration` para configurar bloqueio de objetos (não necessário para sites estáticos).
  # - Para uploads grandes, considere multipart uploads ou AWS CLI diretamente.
}

# Cria uma distribuição do CloudFront para servir os arquivos do bucket S3
resource "aws_cloudfront_distribution" "cdn" {
  origin {
    domain_name = aws_s3_bucket.site_bucket.bucket_regional_domain_name  # Define a origem como o bucket S3
    origin_id   = "S3-site-origin"  # Identificador exclusivo para a origem
  }

  enabled             = true  # Habilita a distribuição do CloudFront
  is_ipv6_enabled     = true  # Permite conexões IPv6
  default_root_object = "index.html"  # Arquivo padrão para a raiz do site

  # Configuração do comportamento de cache padrão
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]  # Permite apenas métodos de leitura
    cached_methods   = ["GET", "HEAD"]  # Armazena no cache apenas esses métodos
    target_origin_id = "S3-site-origin"  # Referência ao `origin_id` acima

    forwarded_values {
      query_string = false  # Ignora strings de consulta (parâmetros na URL) no cache
      cookies {
        forward = "none"  # Não armazena cookies no cache
      }
    }

    viewer_protocol_policy = "redirect-to-https"  # Redireciona HTTP para HTTPS
    min_ttl                = 0  # Tempo mínimo de vida dos objetos no cache em segundos
    default_ttl            = 3600  # TTL padrão de 1 hora
    max_ttl                = 86400  # TTL máximo de 24 horas

    # Alternativas:
    # - Poderia definir `trusted_signers` para permitir acesso somente a usuários autenticados.
    # - `lambda_function_association` poderia ser usada para adicionar Lambda@Edge (ex. modificação de cabeçalhos).
  }

  # Configurações de restrições geográficas
  restrictions {
    geo_restriction {
      restriction_type = "none"  # Não restringe o acesso por região
    }

    # Alternativas:
    # - `whitelist` ou `blacklist` para permitir/bloquear regiões específicas.
  }

  # Configuração do certificado SSL
  viewer_certificate {
    cloudfront_default_certificate = true  # Utiliza o certificado padrão do CloudFront

    # Alternativas:
    # - Use `acm_certificate_arn` para associar um certificado SSL do ACM (para custom domains).
    # - `minimum_protocol_version` pode ser definido para SSL mais restritivo (ex: TLSv1.2_2021).
  }
}

# Exibe a URL da distribuição do CloudFront ao final da execução do Terraform
output "cloudfront_url" {
  value = aws_cloudfront_distribution.cdn.domain_name  # URL da distribuição do CloudFront
  description = "URL da distribuição CloudFront"  # Descrição do output

  # Alternativas:
  # - Poderia usar `aws_s3_bucket.website_endpoint` para o endpoint de um bucket S3 diretamente, sem CloudFront.
}
