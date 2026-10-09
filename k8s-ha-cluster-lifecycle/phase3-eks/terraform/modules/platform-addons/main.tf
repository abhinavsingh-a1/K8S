# Module: platform-addons
# Cluster software every app on this cluster relies on, installed with Helm:
#   - ingress-nginx: Service type LoadBalancer -> AWS creates an NLB
#   - External Secrets Operator: syncs AWS Secrets Manager -> Kubernetes Secrets
# Uninstalling ingress-nginx (terraform destroy of this stack) also deletes
# the NLB, so the network stack can be destroyed cleanly afterwards.

terraform {
  required_providers {
    helm = {
      source = "hashicorp/helm"
    }
  }
}

resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = var.ingress_nginx_chart_version
  namespace        = "ingress-nginx"
  create_namespace = true
  wait             = true
  timeout          = 600

  values = [yamlencode({
    controller = {
      replicaCount = var.ingress_replicas
      # One controller pod per zone where possible
      topologySpreadConstraints = [{
        maxSkew           = 1
        topologyKey       = "topology.kubernetes.io/zone"
        whenUnsatisfiable = "ScheduleAnyway"
        labelSelector = {
          matchLabels = {
            "app.kubernetes.io/name"      = "ingress-nginx"
            "app.kubernetes.io/component" = "controller"
          }
        }
      }]
      service = {
        type = "LoadBalancer"
        annotations = {
          "service.beta.kubernetes.io/aws-load-balancer-type"                              = "nlb"
          "service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled" = "true"
        }
        loadBalancerSourceRanges = var.app_client_cidrs
      }
    }
  })]
}

resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  version          = var.external_secrets_chart_version
  namespace        = var.eso_namespace
  create_namespace = true
  wait             = true
  timeout          = 600

  values = [yamlencode({
    installCRDs  = true
    replicaCount = 2
    leaderElect  = true # only one replica reconciles at a time
    serviceAccount = {
      # Must match the EKS Pod Identity association (module app-secrets)
      name = var.eso_service_account
    }
  })]
}
