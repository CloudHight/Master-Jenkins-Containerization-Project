output "vpc_id" {
  value = aws_vpc.vpc.id
}

output "public_subnet1_id" {
  value = aws_subnet.public_sub1.id
}

output "public_subnet2_id" {
  value = aws_subnet.public_sub2.id
}

output "private_subnet1_id" {
  value = aws_subnet.private_sub1.id
}
output "private_subnet2_id" {
  value = aws_subnet.private_sub2.id
}

output "public_key" {
  value = aws_key_pair.public-key.key_name
}

output "private_key" {
  value = tls_private_key.key.private_key_pem
}

output "vpc_cidr_block" {
  value = aws_vpc.vpc.cidr_block
}
