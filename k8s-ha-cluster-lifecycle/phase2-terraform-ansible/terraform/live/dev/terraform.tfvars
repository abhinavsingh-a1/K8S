# dev environment settings (no secrets in this file - it is committed).

region              = "us-west-2"
project             = "k8s-ha"
environment         = "dev"
owner               = "platform-team"
vpc_cidr            = "10.20.0.0/16"
control_plane_count = 3
worker_count        = 3

# Empty = only your current public IP
admin_cidrs      = []
app_client_cidrs = []
