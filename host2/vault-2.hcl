storage "raft" {
  path    = "/vault/data"
  node_id = "vault-2"
  retry_join {
    leader_api_addr = "http://192.168.200.170:8200"
  }
}

listener "tcp" {
  address         = "0.0.0.0:8200"
  cluster_address = "0.0.0.0:8201"
  tls_disable     = 1
}

api_addr     = "http://192.168.200.171:8200"
cluster_addr = "http://192.168.200.171:8201"
ui           = true
max_lease_ttl     = "24h"
default_lease_ttl = "4h"
