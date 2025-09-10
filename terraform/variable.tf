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