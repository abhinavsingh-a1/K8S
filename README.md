Install minikube (single node k8s cluster) -

https://minikube.sigs.k8s.io/docs/start/?arch=%2Fwindows%2Fx86-64%2Fstable%2F.exe+download

Install kind (n:n master worker cluster) -

https://kind.sigs.k8s.io/docs/user/quick-start/#installing-from-release-binaries

To start cluster on minikuve -

$ minikube start

It will first create VM >> single node k8s cluster will be created.

If you are on MAC / Windows, start minikube cluster with memory -

$ minikube start --memory=4096 --driver=hyperkit

or

$ minikube start --memory=4096 --driver=hvirtualbox

When we run simple command, docker driver is running behind the scene -

$ minikube start

When we run command to get nodes, we can see, there is 1 control plane i.e. 1 control plane & 1 data plane -

<img width="453" height="62" alt="image" src="https://github.com/user-attachments/assets/afc0a6dc-5df1-44ca-9456-e3b2d0d023bd" />

Lets install POD, go to -

https://kubernetes.io/docs/concepts/workloads/pods/

Copy POD.yml & vi POD.yml & paste code. Then run below command to create POD -

<img width="453" height="45" alt="image" src="https://github.com/user-attachments/assets/58aefd4c-2cba-464b-917c-963b0fc2e6a2" />

To get IP address of POD -

<img width="843" height="89" alt="image" src="https://github.com/user-attachments/assets/0ce9ac40-3b8f-4018-92e5-644871fa0229" />

To login to master node / worker node, we have to ssh the node. But minikube have single master worker node so -

<img width="484" height="137" alt="image" src="https://github.com/user-attachments/assets/139b6553-07ad-44e0-9279-38f88752b248" />

curl the node IP & you will see it has started running -

<img width="694" height="522" alt="image" src="https://github.com/user-attachments/assets/44a45e9f-7e52-4426-a4e2-8576bb532162" />

# KUBECTL CHEATSHEET

https://kubernetes.io/de/docs/reference/kubectl/cheatsheet/

Delete POD -

<img width="849" height="121" alt="image" src="https://github.com/user-attachments/assets/8f6eaa99-c336-46bc-adc9-bb12f79e6a4b" />

How to debug POD (here you will get all information about POD & if any error) -

<img width="851" height="958" alt="image" src="https://github.com/user-attachments/assets/a36e19dc-9f99-4340-8c8c-3e0e4c0ef1c5" />
<img width="861" height="182" alt="image" src="https://github.com/user-attachments/assets/387ed269-5d47-40ea-84e5-942d505948b7" />

to see logs thrown by POD -
$ kubectl logs nginx

# Deployment

https://kubernetes.io/docs/concepts/workloads/controllers/deployment/

copy deployment & create deployment.yml -

<img width="486" height="48" alt="image" src="https://github.com/user-attachments/assets/379f0136-8d91-44fa-9b0b-ee89e0c44d99" />


<img width="634" height="213" alt="image" src="https://github.com/user-attachments/assets/79875ada-2146-4831-8d56-e6a57f82c9c2" />


watching pods with live status -

<img width="657" height="108" alt="image" src="https://github.com/user-attachments/assets/2ecf8f4b-626c-4bcb-8cfa-143d01511112" />

Delete the POD -

<img width="674" height="42" alt="image" src="https://github.com/user-attachments/assets/d64a92b6-1c78-439b-a90d-8af7426cdf54" />

Once the pod is deleted, a new pod is created automatically -

<img width="765" height="286" alt="image" src="https://github.com/user-attachments/assets/8d6bb1f5-d252-4df0-b3b8-f006e9b1f213" />

After sometime, you can see, pod is created -

<img width="755" height="279" alt="image" src="https://github.com/user-attachments/assets/e3da602f-819d-421a-b23b-418cbff0aade" />

# SERVICE
















