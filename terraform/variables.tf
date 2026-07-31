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
EOF

terraform/main.tf:

bash
cat > terraform/main.tf << 'EOF'
terraform {
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "3.0.2"
    }
  }
}

provider "docker" {
  host = "unix:///var/run/docker.sock"
}

# Networks
resource "docker_network" "penpot" {
  name = "penpot"
}

resource "docker_network" "internal" {
  name     = "penpot-internal"
  internal = true
}

# Volumes
resource "docker_volume" "postgres" {
  name = "penpot_postgres"
}

resource "docker_volume" "assets" {
  name = "penpot_assets"
}

# Images
resource "docker_image" "frontend" {
  name = "penpotapp/frontend:${var.penpot_version}"
}
resource "docker_image" "backend" {
  name = "penpotapp/backend:${var.penpot_version}"
}
resource "docker_image" "exporter" {
  name = "penpotapp/exporter:${var.penpot_version}"
}
resource "docker_image" "postgres" {
  name = "postgres:15"
}
resource "docker_image" "valkey" {
  name = "valkey/valkey:8.1"
}
resource "docker_image" "nginx" {
  name = "nginx:1.27-alpine"
}

# Database
resource "docker_container" "postgres" {
  name    = "penpot-postgres"
  image   = docker_image.postgres.image_id
  restart = "always"
  env = [
    "POSTGRES_DB=penpot",
    "POSTGRES_USER=penpot",
    "POSTGRES_PASSWORD=${var.db_password}",
  ]
  security_opts = ["no-new-privileges:true"]
  volumes {
    volume_name    = docker_volume.postgres.name
    container_path = "/var/lib/postgresql/data"
  }
  networks_advanced {
    name = docker_network.internal.name
  }
}

# Valkey (redis)
resource "docker_container" "valkey" {
  name          = "penpot-valkey"
  image         = docker_image.valkey.image_id
  restart       = "always"
  security_opts = ["no-new-privileges:true"]
  networks_advanced {
    name = docker_network.internal.name
  }
}

# Backend
resource "docker_container" "backend" {
  name    = "penpot-backend"
  image   = docker_image.backend.image_id
  restart = "always"
  env = [
    "PENPOT_FLAGS=disable-registration disable-telemetry enable-prepl-server enable-log-emails",
    "PENPOT_PUBLIC_URI=https://${var.public_host}",
    "PENPOT_DATABASE_URI=postgresql://penpot-postgres/penpot",
    "PENPOT_DATABASE_USERNAME=penpot",
    "PENPOT_DATABASE_PASSWORD=${var.db_password}",
    "PENPOT_REDIS_URI=redis://penpot-valkey/0",
    "PENPOT_ASSETS_STORAGE_BACKEND=assets-fs",
    "PENPOT_STORAGE_ASSETS_FS_DIRECTORY=/opt/data/assets",
    "PENPOT_SECRET_KEY=${var.secret_key}",
    "PENPOT_TELEMETRY_ENABLED=false",
  ]
  security_opts = ["no-new-privileges:true"]
  volumes {
    volume_name    = docker_volume.assets.name
    container_path = "/opt/data/assets"
  }
  networks_advanced {
    name = docker_network.penpot.name
  }
  networks_advanced {
    name = docker_network.internal.name
  }
  depends_on = [docker_container.postgres, docker_container.valkey]
}

# Exporter
resource "docker_container" "exporter" {
  name    = "penpot-exporter"
  image   = docker_image.exporter.image_id
  restart = "always"
  env = [
    "PENPOT_PUBLIC_URI=http://penpot-frontend:8080",
    "PENPOT_REDIS_URI=redis://penpot-valkey/0",
  ]
  security_opts = ["no-new-privileges:true"]
  networks_advanced {
    name = docker_network.penpot.name
  }
  networks_advanced {
    name = docker_network.internal.name
  }
  depends_on = [docker_container.valkey]
}

# Frontend (not published to host; the proxy handles that)
resource "docker_container" "frontend" {
  name          = "penpot-frontend"
  image         = docker_image.frontend.image_id
  restart       = "always"
  security_opts = ["no-new-privileges:true"]
  networks_advanced {
    name = docker_network.penpot.name
  }
  depends_on = [docker_container.backend, docker_container.exporter]
}

# Reverse proxy with TLS and security headers
resource "docker_container" "proxy" {
  name    = "penpot-proxy"
  image   = docker_image.nginx.image_id
  restart = "always"
  ports {
    internal = 80
    external = 80
  }
  ports {
    internal = 443
    external = 443
  }
  volumes {
    host_path      = "/opt/penpot/proxy/nginx.conf"
    container_path = "/etc/nginx/conf.d/default.conf"
    read_only      = true
  }
  volumes {
    host_path      = "/opt/penpot/proxy/certs"
    container_path = "/etc/nginx/certs"
    read_only      = true
  }
  networks_advanced {
    name = docker_network.penpot.name
  }
  depends_on = [docker_container.frontend]
}
