
























## 🎛️ Instrumentation<br />
- Instrumentation refers to the process of adding monitoring capabilities to your applications, systems, or services.
- This involves embedding/Writting code or using tools to collect metrics, logs, or traces that provide insights into how the system is performing.

## 🎯 Purpose of Instrumentation:<br />
- **Visibility**: It helps you gain visibility into the internal state of your applications and infrastructure.
- **Metrics Collection**: By collecting key metrics like CPU usage, memory consumption, request rates, error rates, etc., you can understand the health and performance of your system.
- **Troubleshooting**: When something goes wrong, instrumentation allows you to diagnose the issue quickly by providing detailed insights.

## ⚙️ How it Works:<br />
- **Code-Level Instrumentation**: You can add instrumentation directly in your application code to expose metrics. For example, in a `Node.js` application, you might use a library like prom-client to expose custom metrics.

## 📈 Instrumentation in Prometheus:
- 📤 **Exporters**: Prometheus uses exporters to collect metrics from different systems. These exporters expose metrics in a format that Prometheus can scrape and store.
    - **Node Exporter**: Collects system-level metrics from Linux/Unix systems.
    - **MySQL Exporter (For MySQL Database)**:  Collects metrics from a MySQL database.
    - **PostgreSQL Exporter (For PostgreSQL Database)**: Collects metrics from a PostgreSQL database.
- 📊 **Custom Metrics**: You can instrument your application to expose custom metrics that are relevant to your specific use case. For example, you might track the number of user logins per minute.

## 📈 Types of Metrics in Prometheus
- 🔄️ **Counter**:
    - A Counter is a cumulative metric that represents a single numerical value that only ever goes up. It is used for counting events like the number of HTTP requests, errors, or tasks completed.
    - **Example**: Counting the number of times a container restarts in your Kubernetes cluster
    - **Metric Example**: `kube_pod_container_status_restarts_total`

- 📏 **Gauge**:
    - A Gauge is a metric that represents a single numerical value that can go up and down. It is typically used for things like memory usage, CPU usage, or the current number of active users.
    - **Example**: Monitoring the memory usage of a container in your Kubernetes cluster.
    - **Metric Example**: `container_memory_usage_bytes`

- 📊 **Histogram**:
    - A Histogram samples observations (usually things like request durations or response sizes) and counts them in configurable buckets.
    - It also provides a sum of all observed values and a count of observations.
    - **Example**: Measuring the response time of Kubernetes API requests in various time buckets.
    - **Metric Example**: `apiserver_request_duration_seconds_bucket`

- 📝 Summary:
    - Similar to a Histogram, a Summary samples observations and provides a total count of observations, their sum, and configurable quantiles (percentiles).
    - **Example**: Monitoring the 95th percentile of request durations to understand high latency in your Kubernetes API.
    - **Metric Example**: `apiserver_request_duration_seconds_sum`


# 🎯 Project Objectives
- 🛠️ **Implement Custom Metrics in Node.js Application**: Use the prom-client library to write and expose custom metrics in the Node.js application.
- 🚨 **Set Up Alerts in Alertmanager**: Configure Alertmanager to send email notifications if a container crashes more than two times.
- 📝 **Set Up Logging**: Implement logging on both application and cluster (node) logs for better observability using EFK stack(Elasticsearch, FluentBit, Kibana).
- 📸 **Implement Distributed Tracing for Node.js Application**: Enhance observability by instrumenting the Node.js application for distributed tracing using Jaeger. enabling better performance monitoring and troubleshooting of complex, multi-service architectures.

# 🏠 Architecture
![Project Architecture](images/architecture.gif)

## 1) Write Custom Metrics
- Please take a look at `day-4/application/service-a/index.js` file to learn more about custom metrics. below is the brief overview
- **Express Setup**: Initializes an Express application and sets up logging with Morgan.
- **Logging with Pino**: Defines a custom logging function using Pino for structured logging.
- **Prometheus Metrics with prom-client**: Integrates Prometheus for monitoring HTTP requests using the prom-client library:
    - `http_requests_total`: counter
    - `http_request_duration_seconds`: histogram
    - `http_request_duration_summary_seconds`: summary
    - `node_gauge_example`: gauge for tracking async task duration
### Basic Routes:
- `/` : Returns a "Running" status.
- `/healthy`: Returns the health status of the server.
- `/serverError`: Simulates a 500 Internal Server Error.
- `/notFound`: Simulates a 404 Not Found error.
- `/logs`: Generates logs using the custom logging function.
- `/crash`: Simulates a server crash by exiting the process.
- `/example`: Tracks async task duration with a gauge.
- `/metrics`: Exposes Prometheus metrics endpoint.
- `/call-service-b`: To call service b & receive data from service b

  --------------------------------------------------------------
  Below file has explanation of all metrics >>

Instrumentation >> application >> Service-a >> index.js ==>>

// Prometheus metrics
Counter ==>>    name: 'http_requests_total', <br />
                Desc : 'Total number of HTTP requests'<br /><br />

Histogram ==>>  name: 'http_request_duration_seconds', <br />
                Desc: 'Duration of HTTP requests in seconds',<br />
                buckets: [0.1, 0.5, 1, 5, 10] // Buckets for the histogram in seconds<br /><br />

Summary ==>>    name: 'http_request_duration_summary_seconds', <br />
                Desc: 'Summary of the duration of HTTP requests in seconds',<br />
                percentiles: [0.5, 0.9, 0.99] // Define your percentiles here<br /><br />

// Gauge metric<br />
Gauge ==>>      name: 'node_gauge_example', <br />
                Desc: 'Example of a gauge tracking async task duration'<br /><br /><br /><br /><br />
--------------------------------------------------------------


## 2) dockerize & push it to the registry
- To containerize the applications and push it to your Docker registry, run the following commands:
```bash
cd day-4

# Dockerize microservice - a
docker build -t <<NAME_OF_YOUR_REPO>>:<<TAG>> application/service-a/ 
# or use abhishekf5/demoservice-a:v

# Dockerize microservice - b
docker build -t <<NAME_OF_YOUR_REPO>>:<<TAG>> application/service-b/ 

or use the pre-built images
- a1abhinavsingh/demoservice-a:v
- a1abhinavsingh/demoservice-b:v

```

Navigate to service-a directory. Login to Docker -

<img width="1200" height="203" alt="image" src="https://github.com/user-attachments/assets/c52f2a99-f587-40bf-82d9-8bac6b5b7e6d" />

Build image for service-a -

$ docker build -t a1abhinavsingh/service-a:v1 .

<img width="1906" height="852" alt="image" src="https://github.com/user-attachments/assets/dbe67631-f7df-4846-a33d-548940a610b3" />

Push image to Docker hub for service-a -

<img width="1458" height="84" alt="image" src="https://github.com/user-attachments/assets/ed4f8941-46bf-467b-af22-345e04c890a5" />

Build image for service-b -

$ docker build -t a1abhinavsingh/service-b:v1 .

<img width="1906" height="852" alt="image" src="https://github.com/user-attachments/assets/dbe67631-f7df-4846-a33d-548940a610b3" />

Push image to Docker hub for service-b -

<img width="1458" height="84" alt="image" src="https://github.com/user-attachments/assets/ed4f8941-46bf-467b-af22-345e04c890a5" />







## 3) Kubernetes manifest
- Review the Kubernetes manifest files located in `day-4/kubernetes-manifest`.
- Apply the Kubernetes manifest files to your cluster by running:
```bash
kubectl create ns dev

kubectl apply -k kubernetes-manifest/
```
--------------------------------------------------------------------------------
Create namespace -

$ kubectl create ns dev

Apply manifest of kubernetes-manifest - 

$ kubectl apply -k kubernetes-manifest/

<img width="1235" height="126" alt="image" src="https://github.com/user-attachments/assets/8003c588-4006-4dec-8d75-5708fbc6da4d" />

Both of the PODs should start running -

<img width="1113" height="101" alt="image" src="https://github.com/user-attachments/assets/a37e6406-6da7-444b-91dc-4d2bde8b5807" />

$ kubectl get svc -n dev

<img width="1084" height="106" alt="image" src="https://github.com/user-attachments/assets/ea3a256d-a470-41d6-9ec8-adf776d9f34f" />

Service A is communicating with Service B internally.

In service external IP will appear in some time. Hit that URL in browser and application will start running-

<img width="1008" height="369" alt="image" src="https://github.com/user-attachments/assets/d6e6c662-9740-45d2-962c-97495f744128" />

It supports many API like -
/healthy
/logs
etc.

<img width="1040" height="297" alt="image" src="https://github.com/user-attachments/assets/58d3f0ca-6af1-4132-819c-e4ab3cab09cb" />

Now lets see the metrics such as http_requests_total is working on prometheus and giving some output -

<img width="733" height="428" alt="image" src="https://github.com/user-attachments/assets/c924f223-c5a9-41d1-a0e6-aed539578f66" />

It is not giging anything because till now service discovery is not enabled. So we have created the prometheus stack but how PROMETHEUS know from which application it has to fetch the cutomer metrics from.

For Service Descovery we have manifest in alerts-alertmanager-servicemonitoring-manifest folder. Just create those.

$ kubectl apply -k alerts-alertmanager-servicemonitoring-manifest/

<img width="868" height="99" alt="image" src="https://github.com/user-attachments/assets/8a5cc097-20bf-4369-8a5b-0072efc266df" />

Lets look in to PROMETHEUS -

<img width="1303" height="880" alt="image" src="https://github.com/user-attachments/assets/15f099b9-893f-4196-a00d-23c7904e5f59" />
--------------------------------------------------------------------------------






## 4) Test all the endpoints
- Open a browser and get the LoadBalancer DNS name & hit the DNS name with following routes to test the application:
    - `/`
    - `/healthy`
    - `/serverError`
    - `/notFound`
    - `/logs`
    - `/example`
    - `/metrics`
    - `/call-service-b`
- Alternatively, you can run the automated script `test.sh`, which will automatically send random requests to the LoadBalancer and generate metrics:
```bash
./test.sh <<LOAD_BALANCER_DNS_NAME>>
```

## 5) Configure Alertmanager
- Review the Alertmanager configuration files located in `day-4/alerts-alertmanager-servicemonitor-manifest` but below is the brief overview
    - Before configuring Alertmanager, we need credentials to send emails. For this project, we are using Gmail, but any SMTP provider like AWS SES can be used. so please grab the credentials for that.
    - Open your Google account settings and search App password & create a new password & put the password in `day-4/alerts-alertmanager-servicemonitor-manifest/email-secret.yml`
    - One last thing, please add your email id in the `day-4/alerts-alertmanager-servicemonitor-manifest/alertmanagerconfig.yml`
- **HighCpuUsage**: Triggers a warning alert if the average CPU usage across instances exceeds 50% for more than 5 minutes.
- **PodRestart**: Triggers a critical alert immediately if any pod restarts more than 2 times.
- Apply the manifest files to your cluster by running:
```bash
kubectl apply -k alerts-alertmanager-servicemonitor-manifest/
```
- Wait for 4-5 minutes and then check the Prometheus UI to confirm that the custom metrics implemented in the Node.js application are available:
    - `http_requests_total`: counter
    - `http_request_duration_seconds`: histogram
    - `http_request_duration_summary_seconds`: summary
    - `node_gauge_example`: gauge for tracking async task duration

## 6) Testing Alerts
- To test the alerting system, manually crash the container more than 2 times to trigger an alert (email notification).
- To crash the application container, hit the following endpoint
- `<<LOAD_BALANCER_DNS_NAME>>/crash`
- You should receive an email once the application container has restarted at least 3 times.
