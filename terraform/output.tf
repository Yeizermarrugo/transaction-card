output "redis_host" {
  value = aws_elasticache_cluster.main_redis.cache_nodes[0].address
}

output "redis_port" {
  value = aws_elasticache_cluster.main_redis.port
}

output "api_invoke_url" {
  value = "${aws_api_gateway_rest_api.card_api.execution_arn}/dev"
}

output "check_balance_queue_url" {
  value = aws_sqs_queue.check_balance.id
}

output "transaction_queue_url" {
  value = aws_sqs_queue.transaction.id
}
