output "public_ip_jenkins" {
  description = "Public IP of the Netflix EC2 instance"
  value       = aws_instance.netflix.public_ip
}