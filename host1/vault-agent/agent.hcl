vault {
  address = "http://vault-1:8200"
  retry {
    num_retries = 5
  }
}

auto_auth {
  method "approle" {
    config = {
      role_id_file_path   = "/vault/approle/role_id"
      secret_id_file_path = "/vault/approle/secret_id"
      remove_secret_id_file_after_reading = false
    }
  }

  sink "file" {
    config = {
      path = "/vault/secrets/.vault-token"
      mode = 0600
    }
  }
}

cache {
  use_auto_auth_token = true
}

listener "tcp" {
  address     = "127.0.0.1:8007"
  tls_disable = true
}

template {
  source      = "/tmp/db.tmpl"
  destination = "/vault/secrets/db.env"
  perms       = 0600
}

template {
  source      = "/tmp/monitoring.tmpl"
  destination = "/vault/secrets/monitoring.env"
  perms       = 0600
}
