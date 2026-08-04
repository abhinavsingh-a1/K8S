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






