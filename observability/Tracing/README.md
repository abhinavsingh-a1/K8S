## 🕵️‍♂️ What is Jaeger?
- Jaeger is an open-source, end-to-end distributed tracing system used for monitoring and troubleshooting microservices-based architectures. It helps developers understand how requests flow through a complex system, by tracing the path a request takes and measuring how long each step in that path takes.

## ❓ Why Use Jaeger?
- In modern applications, especially microservices architectures, a single user request can touch multiple services. When something goes wrong, it’s challenging to pinpoint the source of the problem. Jaeger helps by:

- 🐢 **Identifying bottlenecks**: See where your application spends most of its time.
- 🔍 **Finding root causes of errors**: Trace errors back to their source.
- ⚡ **Optimizing performance**: Understand and improve the latency of services.


## 📚 Core Concepts of Jaeger

- 🛤️ **Trace**: A trace represents the journey of a request as it travels through various services. Think of it as a detailed map that shows every stop a request makes in your system.
- 📏 **Span**: Each trace is made up of multiple spans. A span is a single operation within a trace, such as an API call or a database query. It has a start time and a duration.
- 🏷️ **Tags**: Tags are key-value pairs that provide additional context about a span. For example, a tag might indicate the HTTP method used (GET, POST) or the status code returned.
- 📝 **Logs**: Logs in a span provide details about what’s happening during that operation. They can capture events like errors or important checkpoints.
- 🔗 **Context Propagation**: For Jaeger to trace requests across services, it needs to propagate context. This means each service in the call chain passes along the trace information to the next service.

# 🏠 Architecture
<img width="664" height="864" alt="image" src="https://github.com/user-attachments/assets/559757c0-8981-472c-9a43-5b3203a00081" />




## ⚙️ Setting Up Jaeger

### Step 1: Instrumenting Your Code
- To start tracing, you need to instrument your services. This means adding tracing capabilities to your code. Most popular programming languages and frameworks have libraries or middleware that make this easy.
- We have already instrumented our code using OpenTelemetry libraries/packages. For more details, refer to `instrumentation/application/service-a/tracing.js` or `instrumentation/application/service-b/tracing.js`.


### Step 2: Components of Jaeger
- Jaeger consists of several components:
- Agent: Collects traces from your application.
- Collector: Receives traces from the agent and processes them.
- Query: Provides a UI to view traces.
- Storage: Stores traces for later retrieval (often a database like *Elasticsearch*).

- <img width="863" height="492" alt="image" src="https://github.com/user-attachments/assets/75a49665-2065-492f-8df1-bd13be3541f1" />


Go to logging >> README.md & execute Step 1 to Step 6. Store User name & password with you somewhere. This information will be used in Jaeger installation.

### Step 3: Export Elasticsearch CA Certificate
- This command retrieves the CA certificate from the Elasticsearch master certificate secret and decodes it, saving it to a ca-cert.pem file.
```bash
kubectl get secret elasticsearch-master-certs -n logging -o jsonpath='{.data.ca\.crt}' | base64 --decode > ca-cert.pem
```

### Step 4: Create Tracing Namespace
- Creates a new Kubernetes namespace called tracing if it doesn't already exist, where Jaeger components will be installed.
```bash
kubectl create ns tracing
```

### Step 5: Create ConfigMap for Jaeger's TLS Certificate
- Creates a ConfigMap in the tracing namespace, containing the CA certificate to be used by Jaeger for TLS.
```bash
kubectl create configmap jaeger-tls --from-file=ca-cert.pem -n tracing
```
### Step 6: Create Secret for Elasticsearch TLS
- Creates a Kubernetes Secret in the tracing namespace, containing the CA certificate for Elasticsearch TLS communication.
```bash
kubectl create secret generic es-tls-secret --from-file=ca-cert.pem -n tracing
```
### Step 7: Add Jaeger Helm Repository
- adds the official Jaeger Helm chart repository to your Helm setup, making it available for installations.
```bash
helm repo add jaegertracing https://jaegertracing.github.io/helm-charts

helm repo update
```

### Step 8: Install Jaeger with Custom Values

<img width="756" height="300" alt="image" src="https://github.com/user-attachments/assets/eeb51a79-c68a-470f-af9f-04aab6ee334a" />

- 👉 **Note**: Please update the `password` field and other related field in the `jaeger-values.yaml` file with the password retrieved earlier in day-4 at step 6: (i.e NJyO47UqeYBsoaEU)"
-  Command installs Jaeger into the tracing namespace using a custom jaeger-values.yaml configuration file. Ensure the password is updated in the file before installation.
```bash
helm install jaeger jaegertracing/jaeger -n tracing --values jaeger-values.yaml
```

<img width="1921" height="615" alt="image" src="https://github.com/user-attachments/assets/b639439b-58dd-47fb-828d-c201bff7254d" />

$ kubectl get pods -n logging

<img width="738" height="119" alt="image" src="https://github.com/user-attachments/assets/117f5d96-64af-42fe-a110-900831608166" />


### Step 9: Port Forward Jaeger Query Service
- Command forwards port 8080 on your local machine to the Jaeger Query service, allowing you to access the Jaeger UI locally.
```bash
kubectl port-forward svc/jaeger-query 8080:80 -n tracing

```

Below is UI for Jaeger -

<img width="1244" height="812" alt="image" src="https://github.com/user-attachments/assets/1695f82b-bdb9-4106-a79a-f700b084fe3a" />

Now go to Observability >> Instrumentation >> README.md >> 3) Kubernetes manifest

$ kubectl create ns dev

$ kubectl apply -k kubernetes-manifest/

$ Kubectl get svc -n dev

<img width="1340" height="113" alt="image" src="https://github.com/user-attachments/assets/1c89d0d5-1285-4bb6-9592-0ec3be62c3a4" />

Run the Loadbalancer external IP in browser so that there could be some traces receive in Jeager.

<img width="900" height="178" alt="image" src="https://github.com/user-attachments/assets/1c99b43b-3566-40d3-af03-f4b384f17610" />

Let's hit the /healthy API -

<img width="1003" height="278" alt="image" src="https://github.com/user-attachments/assets/27611c78-815c-4e61-ad76-9d67f1385531" />

Now go back to Jeager UI in browser & refresh, you will be able to see the service -

<img width="1180" height="698" alt="image" src="https://github.com/user-attachments/assets/114b6de7-8c6f-4494-8810-a2a6357005fc" />

Now select any trace -

<img width="1007" height="465" alt="image" src="https://github.com/user-attachments/assets/d912db41-003d-4ff0-856e-7f8f9e75ab5f" />

You will be able to see the spans.

## 🧼 Clean Up
```bash

helm uninstall jaeger -n tracing

helm uninstall elasticsearch -n logging

# Also delete PVC created for elasticsearch

helm uninstall monitoring -n monitoring

cd day-4

kubectl delete -k kubernetes-manifest/

kubectl delete -k alerts-alertmanager-servicemonitor-manifest/

# Delete cluster
eksctl delete cluster --name observability

```
