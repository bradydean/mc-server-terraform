terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.11.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "2.5.1"
    }
  }
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}

resource "helm_release" "helm-consul" {
  name       = "consul"
  repository = "https://helm.releases.hashicorp.com"
  chart      = "consul"
  version    = "0.44.0"
  set {
    name  = "server.replicas"
    value = 1
  }
  set {
    name  = "connectInject.enabled"
    value = "false"
  }
  set {
    name  = "connectInject.replicas"
    value = 1
  }
  set {
    name  = "connectInject.default"
    value = "true"
  }
  set {
    name  = "controller.enabled"
    value = "true"
  }
  set {
    name  = "syncCatalog.enabled"
    value = "true"
  }
}

resource "kubernetes_deployment" "mc-server" {
  metadata {
    name = "mc-server"
  }
  spec {
    strategy {
      type = "Recreate"
    }
    selector {
      match_labels = {
        minecraft = "paper"
      }
    }
    template {
      metadata {
        name = "mc-server-deployment"
        labels = {
          minecraft = "paper"
          routable  = "true"
        }

      }
      spec {
        hostname  = "mc-server"
        subdomain = "mc-server"
        container {
          image       = "amazoncorretto:18"
          name        = "mc-server"
          command     = ["java", "-Xmx3G", "-jar", "paper-1.18.2-378.jar", "nogui"]
          tty         = true
          working_dir = "/paper"
          volume_mount {
            mount_path = "/paper"
            name       = "paper-data"
          }
          security_context {
            run_as_user = 1000
          }
          port {
            container_port = 25565
          }
          port {
            container_port = 8123
          }
        }
        volume {
          name = "paper-data"
          host_path {
            path = "/data/paper"
          }
        }
      }
    }
  }
}

resource "kubernetes_deployment" "mc-waterfall" {
  metadata {
    name = "mc-waterfall"
  }
  spec {
    strategy {
      type = "Recreate"
    }
    selector {
      match_labels = {
        minecraft = "waterfall"
      }
    }
    template {
      metadata {
        name = "mc-waterfall-deployment"
        labels = {
          minecraft = "waterfall"
          routable  = "true"
        }
      }
      spec {
        hostname  = "waterfall"
        subdomain = "mc-server"
        container {
          image       = "amazoncorretto:18"
          name        = "waterfall"
          command     = ["java", "-jar", "waterfall-1.18-488.jar"]
          tty         = true
          working_dir = "/waterfall"
          volume_mount {
            mount_path = "/waterfall"
            name       = "waterfall-data"
          }
          security_context {
            run_as_user = 1000
          }
          port {
            container_port = 25565
          }
        }
        volume {
          name = "waterfall-data"
          host_path {
            path = "/data/waterfall"
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "mc-server-service" {
  metadata {
    name = "mc-server"
  }
  spec {
    cluster_ip = "None"
    selector = {
      routable = "true"
    }
  }
}

resource "kubernetes_service" "mc-waterfall-service" {
  metadata {
    name = "waterfall-service"
    annotations = {
      "consul.hashicorp.com/service-tags" = "traefik.tcp.routers.waterfall.rule=HostSNI(`*`),traefik.tcp.routers.waterfall.entrypoints=minecraft"
      "consul.hashicorp.com/service-name" = "mc-server-service"
    }
  }
  spec {
    selector = {
      minecraft = "waterfall"
    }
    port {
      port        = 25565
      target_port = 25565
    }
  }
}

resource "kubernetes_service" "dynmap-service" {
  metadata {
    name = "dynmap-service"
    annotations = {
      "consul.hashicorp.com/service-tags" = "traefik.http.routers.dynmap.rule=PathPrefix(`/`),traefik.http.routers.dynmap.entrypoints=http"
    }
  }
  spec {
    selector = {
      minecraft = "paper"
    }
    port {
      port        = 80
      target_port = 8123
    }
  }
}

resource "kubernetes_cluster_role" "traefik-role" {
  metadata {
    name = "traefik-ingress-controller"
  }
  rule {
    api_groups = [""]
    resources  = ["services", "endpoints", "secrets"]
    verbs      = ["get", "list", "watch"]
  }
  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["ingresses", "ingressclasses"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_cluster_role_binding" "traefik-role-binding" {
  metadata {
    name = "traefik-role-binding"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "traefik-ingress-controller"
  }
  subject {
    kind      = "ServiceAccount"
    name      = "traefik-ingress-controller"
    namespace = "kube-system"
  }
}

resource "kubernetes_service_account" "traefik-service-account" {
  metadata {
    name      = "traefik-ingress-controller"
    namespace = "kube-system"
  }
}

resource "kubernetes_deployment" "traefik-deployment" {
  metadata {
    name      = "traefik-ingress-controller"
    namespace = "kube-system"
    labels = {
      k8s-app : "traefik-ingress-lb"
    }
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        k8s-app : "traefik-ingress-lb"
      }
    }
    template {
      metadata {
        labels = {
          k8s-app = "traefik-ingress-lb"
          name    = "traefik-ingress-lb"
        }
      }
      spec {
        service_account_name             = "traefik-ingress-controller"
        termination_grace_period_seconds = 60
        container {
          image = "traefik:v2.7"
          name  = "traefik-ingress-lb"
          port {
            name           = "http"
            container_port = 80
          }
          port {
            name           = "admin"
            container_port = 8080
          }
          args = ["--api.insecure=true", "--entryPoints.http.address=:8081", "--entryPoints.minecraft.address=:25565", "--providers.consulCatalog=true", "--providers.consulCatalog.endpoint.tls.insecureSkipVerify=true", "--serversTransport.insecureSkipVerify=true", "--providers.consulCatalog.endpoint.address=consul-consul-server-0.consul-consul-server.default.svc.cluster.local:8500", "providers.consulCatalog.connectAware=true", "providers.consulCatalog.connectByDefault=true"]
        }
      }
    }
  }
}

resource "kubernetes_service" "traefik-service" {
  metadata {
    name      = "traefik-ingress-service"
    namespace = "kube-system"
  }
  spec {
    type = "NodePort"
    selector = {
      k8s-app = "traefik-ingress-lb"
    }
    port {
      port = 80
      name = "web"
    }
    port {
      port = 8080
      name = "admin"
    }
  }
}
