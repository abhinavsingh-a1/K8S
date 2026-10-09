# dev / 10-infra (no secrets here - committed)
region              = "us-west-2"
project             = "k8s-ha-eks"
environment         = "dev"
vpc_cidr            = "10.30.0.0/16"
single_nat_gateway  = true # prod: false (one NAT per AZ)
kubernetes_version  = "1.34" # check standard support before applying
node_instance_types = ["t3.medium"]
node_desired_size   = 3  # one worker per AZ
api_allowed_cidrs   = [] # empty = your current IP
