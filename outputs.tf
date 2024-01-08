output "valheim-ip" {
  description = "Use this IP to connect to the server!"
  value       = aws_eip.valheim-eip.public_ip
}
