# mc-server-terraform

Deploy a Minecraft server with Terraform

# Features

* Paper server
* Dynmap
* Waterfall proxy
* Consul Catalog
* Traefik proxy in front of Waterfall and Dynmap

## Minikube considerations

You need to mount your Paper server directory and Waterfall directory into the minikube host
before deploying. These directories must be pre-populated with the Paper/Waterfall jars and
configuration files.

```shell
minikube mount $HOME/waterfall:/data/waterfall
```

```shell
minikube mount $HOME/paper:/data/paper
```

then, port-forward Traefik to make the services accessible.

```shell
kubectl port-forward --address=0.0.0.0 -n kube-system <traefik-pod> 8081:8081 25565:25565
```

## Sample Waterfall config

Key thing to keep in mind is the server hostname.

```
server_connect_timeout: 5000
listeners:
- query_port: 25577
  motd: \u00A7eClassic survival, for the most part.
  tab_list: GLOBAL_PING
  query_enabled: false
  proxy_protocol: false
  ping_passthrough: true
  priorities:
  - main
  bind_local_address: true
  host: 0.0.0.0:25565
  max_players: 20
  tab_size: 60
  force_default_server: true
  forced_hosts: {}
remote_ping_cache: -1
network_compression_threshold: 256
permissions:
  default: null
  admin: null
log_pings: true
connection_throttle_limit: 3
prevent_proxy_connections: true
timeout: 30000
player_limit: 20
ip_forward: true
groups: {}
remote_ping_timeout: 5000
connection_throttle: 4000
log_commands: false
stats: c4b9cabb-93e9-4bce-93ab-4b18642e6f3e
online_mode: true
forge_support: false
disabled_commands:
- disabledcommandhere
servers:
  main:
    motd: \u00A7eClassic survival, for the most part.
    address: mc-server.mc-server:25565
    restricted: false
```

## Disclaimer

This deployment is NOT production-ready.

* Dynmap runs on HTTP
* Extraneous Traefik routers/services
* Some communication uses self-signed certificates
* Data is persisted on a host volume
* No logging framework
* No automatic backups
