variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-1"
}

variable "transactions_report_bucket" {
  description = "Unique name for transactions report S3 bucket"
  type        = string
  default     = "mi-reporte-transacciones-bucket-2025"
}

variable "catalog_bucket" {
  description = "Unique name for catalog S3 bucket"
  type        = string
  default     = "mi-catalogo-servicios-bucket-2025"
}

variable "core_api_url" {
  description = "Core bank API URL used by transaction lambda (optional)"
  type        = string
  default     = ""
}

variable "core_api_key" {
  description = "Core bank API key (optional)"
  type        = string
  default     = ""
}
