# Django app Deploy & Debug  on minikube

**Setup**

- Run everything in an **Administrator PowerShell**. minikube on Hyper-V needs it, and so does editing the hosts file.
- Work from the `python-web-app` folder, where the Dockerfile and the YAML files live.
- `<pod>` means a pod name copied from `kubectl get pods`.
- The minikube IP can change after a restart, so commands use `$(minikube ip)` instead of a fixed IP.

**Order**

1. Pre-flight cluster checks
2. Image
3. `configmap.yaml`
4. `deployment.yaml`
5. `service.yaml`
6. `ingress.yaml`
7. hosts file and browser

**The debugging loop** works for any resource. Go down the list until you find the problem:

1. `kubectl get <kind>`: does it exist, and what is its status?
2. `kubectl describe <kind> <name>`: read the **Events** section at the bottom.
3. `kubectl logs <pod>`: what does the app say?
4. `kubectl get events --sort-by=.metadata.creationTimestamp`: the cluster-wide timeline of what happened.
5. `kubectl exec -it <pod> -- bash`: look around from inside the container.

**The path a request takes**

&#91;embedded content: request path · 4 layers, 2 inputs, one check each\]

When the browser fails, run the checks from the bottom up. The lowest layer that fails is the one to fix, because every layer above it depends on it.

## Step 0: Pre-flight cluster checks

The cluster must be healthy before you deploy anything. If a check here fails, every later step fails too.

**Deploy**

```powershell
minikube start
```

**Verify**

```powershell
minikube status                    # host, kubelet, apiserver: Running
kubectl get nodes                  # minikube   Ready
kubectl config current-context     # minikube
kubectl cluster-info               # control plane URL responds
minikube ip                        # note this IP; it can change after a restart
```

**Debug**

```powershell
kubectl get pods -A                       # system pods (coredns, etcd, kube-apiserver) should be Running
kubectl describe node minikube            # Conditions: MemoryPressure/DiskPressure should be False
minikube logs --problems                  # only the lines minikube thinks are errors
```

| Symptom | Cause | Fix |
| --- | --- | --- |
| `id_rsa: Access is denied` | PowerShell is not running as Administrator | Reopen PowerShell with **Run as administrator** |
| `kubectl` talks to the wrong cluster | Context points elsewhere | `kubectl config use-context minikube` |
| Node `NotReady` | Cluster still starting, or the VM is short on memory | Wait a minute; else `minikube stop` then `minikube start` |

## Step 1: Image

Build the image inside minikube so Kubernetes finds it locally. The name and tag must match `deployment.yaml` exactly.

**Deploy**

```powershell
minikube image build -t a1abhinavsingh/python-sample-app-demo:v1 .
```

**Verify**

```powershell
minikube image ls | Select-String python-sample
# docker.io/a1abhinavsingh/python-sample-app-demo:v1
```

**Debug**

```powershell
# What ended up in /app? Expect manage.py, requirements.txt, devops, demo, venv1
minikube ssh "docker run --rm a1abhinavsingh/python-sample-app-demo:v1 ls /app"

# Layers and their sizes, to see which step made the image big
minikube ssh "docker history a1abhinavsingh/python-sample-app-demo:v1"

# Run the container once without Kubernetes, then test it
minikube ssh "docker run -d -p 8000:8000 --name django-test a1abhinavsingh/python-sample-app-demo:v1"
curl.exe http://$(minikube ip):8000/demo/
minikube ssh "docker logs django-test"
minikube ssh "docker rm -f django-test"
```

| Symptom | Cause | Fix |
| --- | --- | --- |
| `COPY failed: ... requirements.txt` | File is in `devops/`, not next to the Dockerfile | Remove that line; `COPY devops /app` already copies it |
| `failed to read dockerfile` | File is named `DockerFile` | Rename to `Dockerfile`, or add `-f DockerFile` |
| `can't open file '/app/manage.py'` at run time | Wrong `COPY` source | Check with `ls /app` above |
| Image missing from `minikube image ls` | Built in a different Docker, or a different tag | Rebuild with `minikube image build` and the exact tag |

## Step 2: ConfigMap

Apply the ConfigMap before the Deployment. Pods that mount a missing ConfigMap stay stuck in `ContainerCreating`.

**Deploy**

```powershell
kubectl apply -f configmap.yaml
```

**Verify**

```powershell
kubectl get configmap test-cm
kubectl get configmap test-cm -o yaml     # data: db-port: "3307"
kubectl describe configmap test-cm
```

After Step 3, check the value from inside a pod:

```powershell
kubectl exec deployment/sample-python-app -- ls /opt            # db-port
kubectl exec deployment/sample-python-app -- cat /opt/db-port   # 3307
```

**Debug**

```powershell
# What would apply change? Run this before every apply
kubectl diff -f configmap.yaml

# Events for pods that cannot mount the ConfigMap
kubectl get events --field-selector reason=FailedMount

# Edit the live object (opens Notepad); good for experiments, but the file is the source of truth
kubectl edit configmap test-cm
```

- A pod stuck in `ContainerCreating` shows this in `kubectl describe pod <pod>`: `MountVolume.SetUp failed for volume "db-connection" : configmap "test-cm" not found`.
- Changing a ConfigMap mounted as a volume updates `/opt/db-port` inside running pods within about a minute. Values used as environment variables only change after a pod restart.

## Step 3: Deployment

The Deployment creates a ReplicaSet, which keeps 2 pods running. Most problems show up here, so this step has the most debug commands.

**Deploy**

```powershell
kubectl apply -f deployment.yaml
kubectl rollout status deployment/sample-python-app   # waits until both pods are ready
```

**Verify**

```powershell
kubectl get deployment sample-python-app        # READY 2/2
kubectl get replicaset                          # one ReplicaSet, DESIRED 2, READY 2
kubectl get pods -o wide --show-labels          # 2 pods Running, label app=sample-python-app
kubectl logs deployment/sample-python-app       # Starting development server at http://0.0.0.0:8000/

# Test one pod without a Service; then open http://localhost:8000/demo/ and press Ctrl+C
kubectl port-forward deployment/sample-python-app 8000:8000
```

**Debug: why is a pod not Running?**

```powershell
kubectl get pods -w                              # watch status changes live (Ctrl+C to stop)
kubectl describe pod <pod>                       # read Events at the bottom first
kubectl get events --sort-by=.metadata.creationTimestamp
kubectl get pod <pod> -o yaml                    # status.containerStatuses: state, lastState, exitCode
```

**Debug: what is the app doing?**

```powershell
kubectl logs <pod>                               # current container
kubectl logs <pod> --previous                    # the container that crashed before this one
kubectl logs -f deployment/sample-python-app     # follow live (Ctrl+C to stop)
kubectl logs -l app=sample-python-app --prefix   # all pods, each line tagged with its pod name
```

**Debug: look from inside the container**

```powershell
kubectl exec -it <pod> -- bash                   # a shell inside the pod; type exit to leave
# inside the pod:
ls /app
cat /opt/db-port
python3 -c "import urllib.request as u; print(u.urlopen('http://localhost:8000/demo/').status)"   # 200
```

The Ubuntu image has no `curl`, so the last line uses Python to call the app from inside the pod. A 200 here but a failure from outside means the problem is in the Service or Ingress, not the app.

**Debug: rollouts and self-healing**

```powershell
kubectl rollout history deployment/sample-python-app
kubectl rollout undo deployment/sample-python-app        # back to the previous version
kubectl rollout restart deployment/sample-python-app     # new pods, same spec (e.g. after rebuilding the image)
kubectl scale deployment sample-python-app --replicas=3
kubectl delete pod <pod>                                 # the ReplicaSet creates a replacement within seconds
```

## Step 4: Service

The Service gives the pods one stable address and load-balances across them. It finds pods by label, so a working Service always has **endpoints**.

**Deploy**

```powershell
kubectl apply -f service.yaml
```

**Verify**

```powershell
kubectl get svc python-django-sample-app            # TYPE NodePort, PORT(S) 80:30007/TCP
kubectl describe svc python-django-sample-app       # Selector, TargetPort 8000, Endpoints with 2 IPs
kubectl get endpointslices -l kubernetes.io/service-name=python-django-sample-app
curl.exe http://$(minikube ip):30007/demo/          # your HTML
minikube service python-django-sample-app --url     # prints the NodePort URL
```

**Debug: does the selector match the pods?**

```powershell
kubectl get svc python-django-sample-app -o jsonpath='{.spec.selector}'   # {"app":"sample-python-app"}
kubectl get pods -l app=sample-python-app                                 # same pods should appear
kubectl get pods --show-labels
```

**Debug: test from inside the cluster**

```powershell
# A throwaway busybox pod calls the Service by its DNS name, then deletes itself
kubectl run tmp --rm -it --restart=Never --image=busybox -- wget -qO- http://python-django-sample-app/demo/

# Does the Service name resolve inside the cluster?
kubectl run tmp --rm -it --restart=Never --image=busybox -- nslookup python-django-sample-app
```

**Debug: skip the NodePort**

```powershell
# Forward localhost:8080 to the Service; open http://localhost:8080/demo/
kubectl port-forward svc/python-django-sample-app 8080:80
```

- Pod IPs (`10.244.x.x`) are inside the cluster only. A browser on Windows cannot reach them; use the NodePort URL or port-forward.
- Works from inside the cluster but not via NodePort → check the IP with `minikube ip`.
- Endpoints empty → selector and labels differ, or no pod is Running yet.
- Endpoints present but requests fail → compare the endpoint **port** with the container port (8000).

## Step 5: Ingress

An Ingress is only a set of rules; the NGINX Ingress controller applies them. Check the controller first, then the rule.

**Deploy**

```powershell
minikube addons enable ingress
kubectl get pods -n ingress-nginx       # controller 1/1 Running; the 2 admission pods Completed
kubectl get ingressclass                # nginx
kubectl apply -f ingress.yaml
```

**Verify**

```powershell
kubectl get ingress                     # ADDRESS = minikube IP (can take a minute)
kubectl describe ingress ingress-example   # Rules: foo.bar.com /demo -> python-django-sample-app:80 (pod IPs)
curl.exe -H "Host: foo.bar.com" http://$(minikube ip)/demo/   # your HTML, through port 80
```

**Debug**

```powershell
# Every request NGINX handled: path, status code, and which pod it went to
kubectl logs -n ingress-nginx deployment/ingress-nginx-controller --tail=20

# Full request and response headers
curl.exe -v -H "Host: foo.bar.com" http://$(minikube ip)/demo/

# The NGINX config generated from your Ingress
kubectl exec -n ingress-nginx deployment/ingress-nginx-controller -- cat /etc/nginx/nginx.conf | Select-String foo.bar.com

# The controller's own Service and ports
kubectl get svc -n ingress-nginx
```

**Read the error page: it tells you which layer failed**

| You see | Meaning | Look at |
| --- | --- | --- |
| Plain `404 Not Found` with `nginx` at the bottom | No Ingress rule matched the host or path | `kubectl describe ingress ingress-example` |
| Yellow Django `Page not found (404)` | The Ingress worked; Django has no such URL | `devops/urls.py`, `demo/urls.py` |
| `503 Service Temporarily Unavailable` | The Service has no endpoints | `kubectl get endpointslices -l kubernetes.io/service-name=python-django-sample-app` |
| `502 Bad Gateway` | Pods reached, but nothing listens on that port | Service `targetPort` vs container port 8000 |
| `failed calling webhook "validate.nginx.ingress.kubernetes.io"` on apply | Controller not ready yet | Wait 30 seconds and apply again |
| `ADDRESS` stays empty | Controller not running, or wrong `ingressClassName` | `kubectl get pods -n ingress-nginx`, `kubectl get ingressclass` |

## Step 6: Browser access

`foo.bar.com` is not a real domain, so the Windows hosts file maps it to the minikube IP.

**Deploy**

```powershell
Add-Content -Path C:\Windows\System32\drivers\etc\hosts -Value "`n$(minikube ip) foo.bar.com"
ipconfig /flushdns
```

Then open `http://foo.bar.com/demo/` in the browser. Type the full URL, including `http://`.

**Verify**

```powershell
Get-Content C:\Windows\System32\drivers\etc\hosts | Select-String foo.bar.com
ping foo.bar.com          # first line shows the minikube IP; replies do not matter
curl.exe http://foo.bar.com/demo/
```

**Debug**

```powershell
# After a minikube restart the IP may change; rewrite the line with the current IP
$hosts = "C:\Windows\System32\drivers\etc\hosts"
(Get-Content $hosts) -replace '^\S+\s+foo\.bar\.com', "$(minikube ip) foo.bar.com" | Set-Content $hosts
ipconfig /flushdns
```

- `curl.exe` works but the browser does not → try a private window, and turn off any VPN or proxy.
- The browser switches to `https://` → retype `http://` explicitly.
- `ping` shows an old IP → run the rewrite above.

## Break-and-fix exercises

Each exercise breaks one thing on purpose. Before reading **What you'll see**, try to find the cause yourself with the debugging loop.

**Before you start:** keep your working files untouched and break copies instead.

```powershell
mkdir practice
Copy-Item *.yaml practice\
```

**Reset after every exercise** (applies only the good files in the top folder, not `practice\`):

```powershell
kubectl apply -f .
curl.exe -H "Host: foo.bar.com" http://$(minikube ip)/demo/     # HTML again = reset worked
```

### 1. Warm-up: kill a pod

- **Break:** `kubectl delete pod <pod>`, then `kubectl get pods -w`
- **What you'll see:** a new pod with a new name appears within seconds. The app stays up because the second pod keeps serving.
- **Lesson:** you never fix pods by hand; the ReplicaSet replaces them.

### 2. Wrong image tag

- **Break:** `kubectl set image deployment/sample-python-app python-app=a1abhinavsingh/python-sample-app-demo:v2`
- **What you'll see:** one new pod in `ErrImagePull`, then `ImagePullBackOff`. The two old pods keep running, so the site still works. `kubectl rollout status` hangs.
- **Find it with:** `kubectl describe pod <new pod>` → Events: `Failed to pull image`. `minikube image ls` shows only `:v1`.
- **Fix:** `kubectl rollout undo deployment/sample-python-app`
- **Lesson:** a rolling update does not remove old pods until new ones are ready.

### 3. Missing ConfigMap

- **Break:** `kubectl delete configmap test-cm`, then `kubectl rollout restart deployment/sample-python-app`
- **What you'll see:** new pods stuck in `ContainerCreating`; the old pods keep serving.
- **Find it with:** `kubectl describe pod <new pod>` → `MountVolume.SetUp failed ... configmap "test-cm" not found`.
- **Fix:** `kubectl apply -f configmap.yaml`. The stuck pods start on their own once the mount succeeds.

### 4. Crashing container

- **Break:** in `practice\deployment.yaml`, add under `imagePullPolicy` (same indentation):

  ```yaml
          command: ["bash", "-c", "echo boom; exit 1"]
  ```

  then `kubectl apply -f practice\deployment.yaml`
- **What you'll see:** a new pod in `CrashLoopBackOff` with a growing RESTARTS count.
- **Find it with:** `kubectl logs <pod> --previous` → `boom`. `kubectl describe pod <pod>` → Last State: Terminated, Exit Code: 1.
- **Fix:** `kubectl apply -f deployment.yaml`

### 5. Service selector typo

- **Break:** in `practice\service.yaml`, change the selector to `app: sample-python-ap`, then `kubectl apply -f practice\service.yaml`
- **What you'll see:** NodePort `:30007` refuses connections; `foo.bar.com/demo/` returns **503**.
- **Find it with:** `kubectl describe svc python-django-sample-app` → Endpoints: `<none>`. Compare its Selector with `kubectl get pods --show-labels`.
- **Fix:** `kubectl apply -f service.yaml`

### 6. Wrong targetPort

- **Break:** in `practice\service.yaml`, set `targetPort: 8001`, then apply it.
- **What you'll see:** endpoints exist, but NodePort refuses connections and the Ingress returns **502 Bad Gateway**.
- **Find it with:** `kubectl get endpointslices -l kubernetes.io/service-name=python-django-sample-app` → PORTS 8001, while Django listens on 8000. The busybox `wget` test says `Connection refused`.
- **Fix:** `kubectl apply -f service.yaml`

### 7. Wrong Ingress path

- **Break:** in `practice\ingress.yaml`, set `path: "/bar"`, then apply it.
- **What you'll see:** `foo.bar.com/demo/` → NGINX 404. `foo.bar.com/bar` → the yellow **Django** 404 page listing `demo/` and `admin/`.
- **Find it with:** `kubectl describe ingress ingress-example` → the rule shows `/bar`. The controller logs show which path arrived.
- **Fix:** `kubectl apply -f ingress.yaml`
- **Lesson:** NGINX forwards the path unchanged, so the Ingress path must be a path Django serves.

### 8. Wrong ingress class

- **Break:** in `practice\ingress.yaml`, set `ingressClassName: traefik`, then apply it.
- **What you'll see:** `kubectl get ingress` shows CLASS `traefik` and ADDRESS empty. `foo.bar.com/demo/` → NGINX 404.
- **Find it with:** `kubectl get ingressclass` lists only `nginx`, so no controller owns this Ingress.
- **Fix:** `kubectl apply -f ingress.yaml`

### 9. No pods at all

- **Break:** `kubectl scale deployment sample-python-app --replicas=0`
- **What you'll see:** `foo.bar.com/demo/` → **503**; NodePort refuses connections.
- **Find it with:** `kubectl get deployment` → READY 0/0. Endpoints are empty.
- **Fix:** `kubectl apply -f deployment.yaml` (sets replicas back to 2)

## Cheat sheet: symptom to cause

Find the symptom, run the first command, and read the output before trying a fix.

| Symptom | Likely cause | First command |
| --- | --- | --- |
| Pod `Pending` | Not enough CPU or memory on the node | `kubectl describe pod <pod>` |
| Pod stuck in `ContainerCreating` | ConfigMap or volume missing | `kubectl describe pod <pod>` |
| `ErrImagePull` / `ImagePullBackOff` | Image not in minikube, wrong tag, or `:latest` | `minikube image ls` |
| `CrashLoopBackOff` | The app starts and exits | `kubectl logs <pod> --previous` |
| Pods Running, Service endpoints empty | Selector and labels differ | `kubectl describe svc python-django-sample-app` |
| NodePort refuses connection | No endpoints, or wrong `targetPort` | `kubectl get endpointslices -l kubernetes.io/service-name=python-django-sample-app` |
| NodePort times out | Wrong IP | `minikube ip` |
| NGINX 404 | No Ingress rule matched host or path | `kubectl describe ingress ingress-example` |
| Django 404 (yellow page) | Ingress fine; URL not in Django | Check `urls.py` |
| 503 from NGINX | Service has no endpoints | `kubectl get endpointslices -l kubernetes.io/service-name=python-django-sample-app` |
| 502 from NGINX | Wrong `targetPort` | `kubectl describe svc python-django-sample-app` |
| Ingress `ADDRESS` empty | Controller down or wrong class | `kubectl get pods -n ingress-nginx` |
| Webhook error on `kubectl apply` | Controller not ready yet | Wait 30 seconds and retry |
| `foo.bar.com` resolves to an old IP | minikube IP changed | `ping foo.bar.com` vs `minikube ip` |
| `id_rsa: Access is denied` | PowerShell not running as Administrator | Reopen as Administrator |

## Appendix: final working files and cleanup

These are the versions that worked end to end. Use them to reset if a file gets messed up.

**Dockerfile**

```dockerfile
FROM ubuntu

WORKDIR /app

RUN apt-get update && apt-get install -y python3 python3-pip python3-venv

COPY devops /app

SHELL ["/bin/bash", "-c"]

RUN python3 -m venv venv1 && \
source venv1/bin/activate && \
pip install --no-cache-dir -r requirements.txt

EXPOSE 8000

CMD source venv1/bin/activate && python3 manage.py runserver 0.0.0.0:8000
```

**.dockerignore**

```text
devops/venv
devops/db.sqlite3
**/__pycache__
```

**configmap.yaml**

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: test-cm
data:
  db-port: "3307"
```

**deployment.yaml**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sample-python-app
  labels:
    app: sample-python-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: sample-python-app
  template:
    metadata:
      labels:
        app: sample-python-app
    spec:
      containers:
      - name: python-app
        image: a1abhinavsingh/python-sample-app-demo:v1
        imagePullPolicy: IfNotPresent
        volumeMounts:
        - name: db-connection
          mountPath: /opt
        ports:
        - containerPort: 8000
      volumes:
        - name: db-connection
          configMap:
            name: test-cm
```

**service.yaml**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: python-django-sample-app
spec:
  type: NodePort
  selector:
    app: sample-python-app
  ports:
    - port: 80
      targetPort: 8000
      nodePort: 30007
```

**ingress.yaml**

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ingress-example
spec:
  ingressClassName: nginx
  rules:
  - host: "foo.bar.com"
    http:
      paths:
      - pathType: Prefix
        path: "/demo"
        backend:
          service:
            name: python-django-sample-app
            port:
              number: 80
```

**Cleanup**

```powershell
kubectl delete -f ingress.yaml -f service.yaml -f deployment.yaml -f configmap.yaml
Remove-Item -Recurse practice
minikube stop
```

Finally, open `C:\Windows\System32\drivers\etc\hosts` in Notepad as Administrator and delete the `foo.bar.com` line.
