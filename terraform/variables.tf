variable "penpot_version" {
  default = "2.4.3"
}

variable "public_host" {
  default = "127.0.0.1"
}

variable "db_password" {
  sensitive = true
}

variable "secret_key" {
  sensitive = true
}
