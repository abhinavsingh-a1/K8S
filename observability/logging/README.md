# 🔍 Logging overview
- Logging is crucial in any distributed system, especially in Kubernetes, to monitor application behavior, detect issues, and ensure the smooth functioning of microservices.


## 🚀 Importance:
- **Debugging**: Logs provide critical information when debugging issues in applications.
- **Auditing**: Logs serve as an audit trail, showing what actions were taken and by whom.
- **Performance** Monitoring: Analyzing logs can help identify performance bottlenecks.
- **Security**: Logs help in detecting unauthorized access or malicious activities.

## 🛠️ Tools Available for Logging in Kubernetes
- 🗂️ EFK Stack (Elasticsearch, Fluentbit(deployed as deamon set: deployed at each node of cluster), Kibana)
- 🗂️ EFK Stack (Elasticsearch, FluentD, Kibana)
- 🗂️ ELK Stack (Elasticsearch, Logstash, Kibana)
- 📊 Promtail + Loki + Grafana

## 📦 EFK Stack (Elasticsearch, Fluentbit, Kibana)
- EFK is a popular logging stack used to collect, store, and analyze logs in Kubernetes.
- **Elasticsearch**: Stores and indexes log data for easy retrieval.
- **Fluentbit**: A lightweight log forwarder that collects logs from different sources and sends them to Elasticsearch.
- **Kibana**: A visualization tool that allows users to explore and analyze logs stored in Elasticsearch.

<img width="863" height="492" alt="image" src="https://github.com/user-attachments/assets/cd18661c-1f13-49fc-bfce-2c2edcd88e8d" />



# 🏠 Architecture
<img width="660" height="860" alt="image" src="https://github.com/user-attachments/assets/fbd3d166-1632-4435-8c1f-8d38decc8418" />



## 📝 Step-by-Step Setup

### 1) Create IAM Role for Service Account
```bash
eksctl create iamserviceaccount \
    --name ebs-csi-controller-sa \
    --namespace kube-system \
    --cluster observability \
    --role-name AmazonEKS_EBS_CSI_DriverRole \
    --role-only \
    --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
    --approve
```
- This command creates an IAM role for the EBS CSI controller.
- IAM role allows EBS CSI controller to interact with AWS resources, specifically for managing EBS volumes in the Kubernetes cluster.
- We will attach the Role with service account

### 2) Retrieve IAM Role ARN
```bash
ARN=$(aws iam get-role --role-name AmazonEKS_EBS_CSI_DriverRole --query 'Role.Arn' --output text)
```
- Command retrieves the ARN of the IAM role created for the EBS CSI controller service account.

### 3) Deploy EBS CSI Driver
```bash
eksctl create addon --cluster observability --name aws-ebs-csi-driver --version latest \
    --service-account-role-arn $ARN --force
```
- Above command deploys the AWS EBS CSI driver as an addon to your Kubernetes cluster.
- It uses the previously created IAM service account role to allow the driver to manage EBS volumes securely.

### 4) Create Namespace for Logging
```bash
kubectl create namespace logging
```

### 5) Install Elasticsearch on K8s

```bash
helm repo add elastic https://helm.elastic.co

helm install elasticsearch \
 --set replicas=1 \
 --set volumeClaimTemplate.storageClassName=gp2 \
 --set persistence.labels.enabled=true elastic/elasticsearch -n logging
```
- Installs Elasticsearch in the `logging` namespace.
- It sets the number of replicas, specifies the storage class, and enables persistence labels to ensure
data is stored on persistent volumes.

### 6) Retrieve Elasticsearch Username & Password
```bash
# for username
kubectl get secrets --namespace=logging elasticsearch-master-credentials -ojsonpath='{.data.username}' | base64 -d
# for password
kubectl get secrets --namespace=logging elasticsearch-master-credentials -ojsonpath='{.data.password}' | base64 -d
```
- Retrieves the password for the Elasticsearch cluster's master credentials from the Kubernetes secret.
- The password is base64 encoded, so it needs to be decoded before use.
- 👉 **Note**: Please write down the password for future reference

### 7) Install Kibana
```bash
helm install kibana --set service.type=LoadBalancer elastic/kibana -n logging
```
- Kibana provides a user-friendly interface for exploring and visualizing data stored in Elasticsearch.
- It is exposed as a LoadBalancer service, making it accessible from outside the cluster.

### 8) Install Fluentbit with Custom Values/Configurations
- 👉 **Note**: Please update the `HTTP_Passwd` field in the `fluentbit-values.yml` file with the password retrieved earlier in step 6: (i.e NJyO47UqeYBsoaEU)"
<img width="669" height="807" alt="image" src="https://github.com/user-attachments/assets/3cdaa4cc-9bbe-46fb-a589-83bcb72a4b02" />

```bash
helm repo add fluent https://fluent.github.io/helm-charts
helm install fluent-bit fluent/fluent-bit -f fluentbit-values.yaml -n logging
```

Lets verify -
$ kubectl get PODS -n logging
<img width="947" height="150" alt="image" src="https://github.com/user-attachments/assets/f541c5ee-6743-49b4-980f-ada428a45690" />
$ kubectl get svc -n logging
<img width="1913" height="274" alt="image" src="https://github.com/user-attachments/assets/360648bc-051d-410b-b691-5dcbf1e64921" />

Open URL in browser. Provide Base64 encoded password which we copied earlier.
<img width="764" height="453" alt="image" src="https://github.com/user-attachments/assets/b6530b56-c27c-4863-8138-fa08dfab901e" />

Kibana dashboard will look like below -
<img width="1211" height="706" alt="image" src="https://github.com/user-attachments/assets/410df224-6046-47a0-92ea-dcb34329a8c3" />



Once you start getting logs after installing application, go to Kibana dashboard & create dataview -
<img width="1379" height="869" alt="image" src="https://github.com/user-attachments/assets/88ed83f7-28d4-4901-b6ad-cc719b567d92" />

You can easily see, logs are displayed below -
<img width="1918" height="931" alt="image" src="https://github.com/user-attachments/assets/2c5bf42a-87c3-4664-a913-b76d2246f073" />

Lets have a look at fluentbit_values.yml file -
- First part is service in which we define, it is ClusterIP, NodePort, LoadBalancer with it PORT.
- <img width="650" height="540" alt="image" src="https://github.com/user-attachments/assets/d47cde26-1df0-42e2-b3d6-984224d0df2d" />
- Next thing is INPUT, from where INPUT is coming from. In our case input is coming from all the containers -
- <img width="616" height="482" alt="image" src="https://github.com/user-attachments/assets/1bddc696-eb51-4e64-b726-06e6a6cd4584" />
- Next we can see filter are set. Here we have used LUA script in which we have ignored logging namespace logs -
- <img width="610" height="484" alt="image" src="https://github.com/user-attachments/assets/28462b04-0a4d-4fed-ba94-e33b6e6d2fed" />
- LUA script is written here -
- <img width="1092" height="729" alt="image" src="https://github.com/user-attachments/assets/fe0a4a2d-06e0-4ece-8faa-13362bd1617a" />
- Finally OUTPUT where logs will be forwarded -
- <img width="760" height="804" alt="image" src="https://github.com/user-attachments/assets/1f48fe22-ed91-47d7-abc3-4ce661a3b72c" /><br />
Host elasticsearch-master <br />
Port 9200<br />
HTTP_User elastic<br />
HTTP_Passwd cbTQj1qxRIPNF5uc<br />
<br />
If you are running on EKS cluster, then make sure TLS is ON otherwise connection will not establish.

## ✅ Conclusion
- We have successfully installed the EFK stack in our Kubernetes cluster, which includes Elasticsearch for storing logs, Fluentbit for collecting and forwarding logs, and Kibana for visualizing logs.
- To verify the setup, access the Kibana dashboard by entering the `LoadBalancer DNS name followed by :5601 in your browser.
    - `http://LOAD_BALANCER_DNS_NAME:5601`
- Use the username and password retrieved in step 6 to log in.
- Once logged in, create a new data view in Kibana and explore the logs collected from your Kubernetes cluster.

## 🧼 Clean Up
```bash

helm uninstall monitoring -n monitoring

helm uninstall fluent-bit -n logging

helm uninstall elasticsearch -n logging

helm uninstall kibana -n logging

cd day-4

kubectl delete -k kubernetes-manifest/

kubectl delete -k alerts-alertmanager-servicemonitor-manifest/


eksctl delete cluster --name observability

```
