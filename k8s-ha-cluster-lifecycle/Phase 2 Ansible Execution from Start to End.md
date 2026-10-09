# Phase 2 Ansible: Execution from Start to End

Oct 9, 2026 · @Abhinav

`ansible-playbook site.yml` runs 9 plays from 5 playbooks, top to bottom. Each play targets one host group from the dynamic inventory, and runs its roles left to right. The sections below follow that order, from the one-time setup to the last task.

## The big picture

&#91;embedded content: site.yml: 5 playbooks, 9 plays, 12 roles\]

Only the prerequisite plays and the joins touch many nodes. Everything that talks to the Kubernetes API runs on the bootstrap control plane, cp-1, through kubectl.

## One-time setup

These run once per machine and environment, before the first playbook.

| Command | What it does | Result |
| --- | --- | --- |
| `run.sh deps` | `ansible-galaxy collection install -r requirements.yml -p ./collections` | The `amazon.aws` collection (dynamic inventory plugin) in `ansible/collections/`, pinned to `>=9.0.0,<11.0.0`. boto3/botocore must be in Ansible's Python (`pipx inject ansible boto3 botocore`) |
| `run.sh vault-init` (part 1) | `openssl rand -base64 32` into `~/.ansible/vault/k8s-ha-dev.pass`, mode 600 | The **vault password**, outside the repository. Back it up in a password manager |
| `run.sh vault-init` (part 2) | Generates a 50-character Django key and a 32-byte etcd key, and pipes the YAML into `ansible-vault encrypt --encrypt-vault-id dev --output .../vault.yml` | `inventories/dev/group_vars/all/vault.yml` starting with `$ANSIBLE_VAULT;1.2;AES256;dev`. The plaintext never touches the disk. This file **is committed** |
| `run.sh fetch-key` (after Terraform) | `aws secretsmanager get-secret-value` for the secret named in the Terraform output | `~/.ssh/k8s-ha-dev.pem`, mode 600 |

The vault file is safe to commit because it's AES-256 encrypted. What must never be committed is the password file. `.gitignore` covers the key and kubeconfig files; the password lives outside the project entirely.

## Before the first task runs

You type `ansible-playbook site.yml` in the `ansible/` folder. Before any server is touched, Ansible does five things.

**1. Find the configuration.** Ansible uses the first config it finds: the `ANSIBLE_CONFIG` variable, then `./ansible.cfg` in the current folder, then `~/.ansible.cfg`, then `/etc/ansible/ansible.cfg`. That's why you run from `ansible/`, and why WSL's `/mnt/...` drives break things: Ansible ignores an `ansible.cfg` in a world-writable folder. From our `ansible.cfg` it learns:

- `inventory = inventories/dev`
- `roles_path = roles`
- `collections_path = ./collections:~/.ansible/collections`
- `forks = 10`
- `vault_identity_list = dev@~/.ansible/vault/k8s-ha-dev.pass`
- `[inventory] enable_plugins` lets the `aws_ec2` plugin load
- `ssh_args` with `UserKnownHostsFile=/dev/null`, because AWS reuses public IPs

**2. Load the vault secret.** The vault id `dev` and its password file are registered. Nothing is decrypted yet. Ansible decrypts `vault.yml` in memory the first time a variable from it is needed.

**3. Build the inventory.** Ansible parses every file in `inventories/dev/`. `aws_ec2.yml` starts with `plugin: amazon.aws.aws_ec2`, so the plugin runs:

- It calls EC2 `DescribeInstances` in `us-west-2`, filtered to `tag:Project=k8s-ha`, `tag:Environment=dev`, and the state `running`.
- `hostnames: [tag:Name]` names each host after its Name tag: `k8s-ha-dev-cp-1` … `k8s-ha-dev-worker-3`.
- `compose` adds host variables from the API data: `ansible_host` = public IP, `private_ip`, `node_az`, `node_instance_type`.
- `groups` builds groups from tag conditions:

| Group | Condition | Hosts (dev) |
| --- | --- | --- |
| `k8s_cluster` | always | all 6 |
| `control_plane` | `Role == control-plane` | cp-1, cp-2, cp-3 |
| `control_plane_bootstrap` | control plane and `Bootstrap == true` | cp-1 |
| `control_plane_joiners` | control plane and not Bootstrap | cp-2, cp-3 |
| `workers` | `Role == worker` | worker-1, -2, -3 |

Check the result any time with `ansible-inventory --graph`, or `ansible-inventory --host k8s-ha-dev-cp-1`.

**4. Attach variables.** Files in `inventories/dev/group_vars/<group>/` apply to every host in that group:

- `all/main.yml` holds the settings and the secret indirection, for example `django_secret_key: "{{ vault_django_secret_key }}"`.
- `all/terraform.yml` holds what Terraform wrote: `api_endpoint`, `aws_region` and so on.
- `all/vault.yml` holds the encrypted `vault_*` values.
- `control_plane/main.yml` holds the encryption and kubeadm config paths, for control planes only.
- Role `defaults/main.yml` give each role its lowest-priority defaults.

The main levels, from low to high: role defaults, then group\_vars/all, then group\_vars/\<group>, then host\_vars, then play vars, then registered results and `set_fact`, then `-e` on the command line (which always wins).

**5. Expand the playbook.** `site.yml` contains only `import_playbook` lines. Imports are static, so Ansible inlines the 5 playbooks into one list of plays before running anything.

## How Ansible runs a play

The same rules apply to every play below.

- **Plays run in order, one at a time.** A play = a host pattern (`hosts:`) + settings + roles or tasks. The next play starts only when the previous one has finished on all its hosts.
- **Roles inside a play run in order.** Each role's `tasks/main.yml` runs top to bottom. `import_tasks` is inlined when the playbook is read; `include_role` / `include_tasks` are loaded when reached.
- **Strategy `linear` (the default).** Task 1 runs on every host of the play, then task 2 on every host, and so on. Up to `forks = 10` hosts run in parallel, so all 6 nodes work at the same time.
- **`serial: 1`** turns a play into batches of one host. The whole play finishes on cp-2 before it starts on cp-3. We need this because etcd adds one member at a time.
- **`gather_facts: true`** runs the `setup` module first, collecting OS, CPU and network facts. Only the prerequisites play needs facts; the others skip it to save time.
- **`become: true`** runs tasks with sudo. The kubectl tasks set `become: false` so they use ubuntu's `~/.kube/config`.
- **A failed task** removes that host from the rest of the play. Other hosts continue, and at the end you see `failed=1` for it in the recap. Our join tasks would fail anyway if the bootstrap node failed, so you fix the cause and rerun.
- **Handlers** (`notify: Restart containerd`) run once, at the end of the play, and only if something notified them. `meta: flush_handlers` in the containerd role forces the restart right there, because kubeadm needs the final config.
- **Idempotency.** Every task checks first and changes only what differs: `copy`/`template` compare content, `apt state=present` skips installed packages, and kubeadm tasks first `stat` `/etc/kubernetes/admin.conf` or `kubelet.conf`. `changed_when` tells Ansible when a `command` actually changed something. A second run of `site.yml` should show almost only `ok`.

## Playbook by playbook

### 00-preflight.yml: check inputs before touching any server

One play on `localhost` (`connection: local`), so it runs on your machine.

1. **Hand-off file exists.** It asserts that `api_endpoint` is set, which proves Terraform wrote `terraform.yml`.
2. **Vault decrypts and the keys look valid.** It asserts that `vault_django_secret_key` exists and that `vault_etcd_encryption_key` is 44 base64 characters (32 bytes). This is the first moment `vault.yml` is decrypted, and a wrong password fails here. `no_log` hides the values.
3. **Inventory has the right shape.** It asserts exactly one bootstrap control plane, an odd number of control planes, and at least one worker.
4. **The SSH key exists.** It checks for `~/.ssh/k8s-ha-dev.pem`.
5. **Port 22 is open on all 6 nodes.** `wait_for` checks each one, so a just-booted instance doesn't fail the next playbook.

### 10-node-prereqs.yml: Step 4, prepare every node

**Play 1** · hosts `k8s_cluster` (6) · `become`, `gather_facts`

| Role | Tasks, in order | Changes on the node |
| --- | --- | --- |
| `os_prereqs` | Set the hostname to the inventory name, swap off, comment swap out of fstab, write and load the modules `overlay` and `br_netfilter`, write the sysctl file and apply it if changed, install base apt packages | The hostname becomes the Kubernetes node name |
| `containerd` | Install it, generate the default config once (`creates:`), set `SystemdCgroup = true` (notify restart), write `/etc/crictl.yaml`, start and enable, **flush handlers** | containerd restarted with the systemd cgroup driver |
| `kube_packages` | Download the repo key, write the repo, install `kubelet kubeadm kubectl cri-tools`, hold them, write `/etc/default/kubelet` with `--node-ip` and zone/region/instance-type labels taken from the **inventory** (no metadata calls), enable kubelet, run `crictl info` | kubelet enabled; it crash-loops until init/join, which is expected |

**Play 2** · hosts `control_plane` (3) · role `etcd_encryption`: it creates `/etc/kubernetes/enc` (mode 700) and templates `encryption-config.yaml` (mode 600) with the secretbox key from Vault, under `no_log`. It must exist on **every** control plane **before** kubeadm starts an API server there.

### 20-cluster.yml: Step 5, build the HA cluster

| Play | Hosts | Role(s) | What happens |
| --- | --- | --- | --- |
| 5a | `control_plane_bootstrap` (cp-1) | `kubeadm_init`, `cni_flannel` | `stat admin.conf` → read `kubeadm version` → template `kubeadm-config.yaml` (InitConfiguration + ClusterConfiguration: NLB endpoint, pod CIDR, cert SAN, `encryption-provider-config` flag and volume, 5-minute API timeout) → wait for NLB DNS → **`kubeadm init --config ... --upload-certs`** only if not initialised → copy the kubeconfig to ubuntu → **every run**: new join token (2 h) + re-upload certs for a fresh certificate key → `set_fact join_command, certificate_key` → Flannel `kubectl apply` + wait for its DaemonSet |
| 5b | `control_plane_joiners` (cp-2, cp-3), **`serial: 1`** | `kubeadm_join_control_plane` | `stat admin.conf` → `kubeadm join <NLB>:6443 --token .. --discovery-token-ca-cert-hash .. --control-plane --certificate-key .. --apiserver-advertise-address <private_ip>` → kubeconfig via `include_role kubeadm_init tasks_from kubeconfig.yml`. cp-2 completes fully before cp-3 starts |
| 5c | `workers` (3, in parallel) | `kubeadm_join_worker` | `stat kubelet.conf` → `kubeadm join` with the worker command |
| 5d | `control_plane_bootstrap` | `cluster_finalize` | Label the workers, `kubectl wait` until all 6 nodes are Ready, show nodes and zones, `etcdctl member list` (expect 3), **fetch** the kubeconfig to `ansible/kubeconfig-dev` |

### 30-app.yml: Step 6, secrets first, then the app

One play on `control_plane_bootstrap`, running two roles in order:

- **`app_secrets`.** It renders `django-secrets.yaml.j2` (a Secret with `stringData.DJANGO_SECRET_KEY`) and pipes it into `kubectl apply -f -` via `stdin`, under `no_log`. If Docker Hub credentials are in Vault, it also creates `regcred` (a dockerconfigjson Secret) and patches the default service account. Then it records `app_secrets_changed`.
- **`app_deploy`.** It copies `k8s/` from the repository root, then applies `configmap`, `django-config`, `deployment`, `pdb` and `service` in that order. If the secret changed, it runs `rollout restart` (env vars are read only at pod start). Then `rollout status`, a list of pods per node, and an HTTP 200 check on `localhost:30007/demo/`.

### 40-ingress.yml: Step 7, ingress

One play on `control_plane_bootstrap`, role `ingress_nginx`, in five steps:

1. Apply the bare-metal ingress-nginx manifest.
2. Patch the HTTP NodePort to 30080; the NLB forwards port 80 there.
3. Scale the controller to 2 replicas and wait.
4. Apply `ingress.yaml`, retrying up to 12 times while the admission webhook starts.
5. Check for HTTP 200 on `localhost:30080/demo/` with `Host: foo.bar.com`, then print the curl and browser instructions.

The recap at the end lists `ok / changed / unreachable / failed / skipped` per host. On a healthy first run, every host shows `failed=0`.

## How secrets flow from Vault to the pod

The Django secret key passes through these hands, and is never written in plaintext to disk or logs:

1. **At rest in Git:** `vault.yml` holds `vault_django_secret_key`, AES-256 encrypted.
2. **In Ansible's memory:** the first time a play needs it, Ansible decrypts it with the password from `~/.ansible/vault/k8s-ha-dev.pass`.
3. **The indirection:** `group_vars/all/main.yml` says `django_secret_key: "{{ vault_django_secret_key }}"`. Roles only use `django_secret_key`, so anyone reading `main.yml` sees which values are secret and where they come from.
4. **To the server:** the template is rendered in memory and sent over SSH as kubectl's **stdin**. There's no temporary file, and `no_log: "{{ hide_secrets }}"` keeps it out of the console and logs.
5. **In Kubernetes:** the API server receives the Secret and, because of `--encryption-provider-config`, **encrypts it with secretbox** before writing it to etcd. The etcd key itself also came from Vault (`vault_etcd_encryption_key`, Play 2 of 10-node-prereqs).
6. **In the pod:** the Deployment's `envFrom.secretRef: django-secrets` makes `DJANGO_SECRET_KEY` an environment variable, and `settings.py` reads it with `os.environ.get`.

Proof: `playbooks/90-debug.yml` reads the raw etcd value with `etcdctl` and prints `ENCRYPTED (k8s:enc:secretbox:v1:key1)`, or a warning if it isn't encrypted.

The kubeadm join token and certificate key are also secrets. They are created fresh on every run, last 2 hours, live only in Ansible's memory (`set_fact`), and every task that touches them has `no_log`. To debug a join, run with `-e hide_secrets=false`, but never in CI logs.

**Rotating the Django key:** run `ansible-vault edit inventories/dev/group_vars/all/vault.yml`, change the value, then `ansible-playbook playbooks/30-app.yml`. The Secret is updated (changed), so `app_deploy` restarts the pods.

**Rotating the etcd key** needs more care. Add `key2` as the first key and keep `key1` second, roll the API servers one at a time, rewrite all Secrets (`kubectl get secrets -A -o json | kubectl replace -f -`), then remove `key1`. This project doesn't automate it.

## How data passes between plays

Each play only sees its own hosts, but some values must travel from one host to another. The join command is created on cp-1 and needed on 5 other machines. Ansible solves this with **host variables that live in memory for the whole `ansible-playbook` run**:

1. On cp-1 (play 5a), `set_fact` stores `join_command` and `certificate_key` as host variables of `k8s-ha-dev-cp-1`.
2. In play 5b, on cp-2, the task reads `hostvars[groups['control_plane_bootstrap'][0]]['join_command']`. In words: "the `join_command` variable of the first host in the bootstrap group".
3. Play 5c reads the same value for the workers.

Two things follow:

- The facts exist only during one run. If you run `playbooks/20-cluster.yml` again later, play 5a recreates them first. That's why token creation isn't skipped on reruns.
- You can't run play 5b alone, for example with `--limit k8s-ha-dev-cp-2`. Without cp-1 in the run there's no `join_command`. Run the whole `20-cluster.yml`; the `stat` checks skip what's already done.

The same idea, `set_fact` then a later read, carries `app_secrets_changed` from role `app_secrets` to role `app_deploy` on the same host.

## Running parts, dry runs and second runs

| Goal | Command (from `ansible/`) |
| --- | --- |
| Everything, Steps 4-7 | `ansible-playbook site.yml` |
| Only redeploy the app after changing manifests or vault | `ansible-playbook playbooks/30-app.yml` |
| Prepare a newly added worker and join it | `ansible-playbook playbooks/10-node-prereqs.yml playbooks/20-cluster.yml` (existing nodes are skipped by the `stat` checks) |
| See what would change, without changing anything | `ansible-playbook site.yml --check --diff` (`command` tasks are skipped in check mode, so the report is partial) |
| Step through tasks one by one | `ansible-playbook site.yml --step` |
| Restart from a specific task after a fix | `ansible-playbook playbooks/20-cluster.yml --start-at-task "kubeadm join (worker)"` |
| Limit to some hosts (where no cross-host facts are needed) | `ansible-playbook playbooks/10-node-prereqs.yml --limit workers` |
| More output | `-v` (task results), `-vvv` (SSH details), `-vvvv` (connection debugging) |
| One ad-hoc command on a group | `ansible control_plane -a "kubectl get nodes"` |
| Health report | `ansible-playbook playbooks/90-debug.yml` |

**What a second run of `site.yml` looks like:** preflight is `ok`. Prerequisites are all `ok`, except the swap and modprobe commands, which are marked `changed_when: false`. In 20-cluster, init and joins are **skipped**, but token creation shows `changed`, because it's new every run. In the app play, applies show `ok` (unchanged) and the rollout restart is skipped. That's idempotency: running again repairs drift and leaves a correct cluster alone.

## Troubleshooting by phase

| Phase | Message | Cause and fix |
| --- | --- | --- |
| Config | `[WARNING]: Ansible is being run in a world writable directory` | Project on `/mnt/...` in WSL. Copy it to `~/` |
| Vault | `Attempting to decrypt but no vault secrets found` | Password file missing. Check `ls ~/.ansible/vault/`, or run `run.sh vault-init` |
| Vault | `Decryption failed (no vault secrets were found that could decrypt)` | Wrong password file, or `vault.yml` encrypted with another vault id |
| Inventory | `Failed to parse ... aws_ec2.yml` / `boto3 required` | `pipx inject ansible boto3 botocore`, `run.sh deps` |
| Inventory | Empty groups in `ansible-inventory --graph` | No running instances with `Project=k8s-ha` and `Environment=dev`. Run `terraform apply` first; check AWS credentials and region |
| Preflight | `api_endpoint missing` | `group_vars/all/terraform.yml` wasn't generated. Run `terraform apply` |
| SSH | `UNREACHABLE ... Permission denied (publickey)` | Run `run.sh fetch-key`; the key must be mode 600 |
| SSH | `UNREACHABLE ... timed out` | Your IP changed. Run `terraform apply` again to update the security group rules |
| 10 | `apt` lock / repository errors | Ubuntu's first-boot updates are still running. Rerun the playbook |
| 20 / 5a | `kubeadm init` timeout | On cp-1: `sudo journalctl -u kubelet -n 50`, `sudo crictl ps -a`. Check NLB target health for `api` |
| 20 / 5b | `error downloading certs` / `certificate key expired` | The key lasts 2 hours. Rerun `20-cluster.yml`; play 5a issues a fresh one |
| 20 / 5b | `'dict object' has no attribute 'join_command'` | You limited the run so cp-1 wasn't included. Run the whole playbook |
| 30 | Pods `CreateContainerConfigError` | A referenced Secret is missing. Both refs are `optional: true` here, so check `kubectl describe pod` |
| 40 | Webhook error after 12 retries | `kubectl -n ingress-nginx get pods`; the controller isn't Ready |

Debug any failing task with `-vvv`, and with `-e hide_secrets=false` if the hidden output is what you need. Read the `msg` / `stderr` in the failure output first; the module prints the remote command's real error there.
