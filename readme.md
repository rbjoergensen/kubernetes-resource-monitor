### Kubernetes resource collector

Docker image for collecting resource usage and pod and deployment statuses in Kubernetes and sending them to Elasticsearch.

The following environment variables are required to run.

| Name          | Example                         | Description                                           |
|---------------|---------------------------------|-------------------------------------------------------|
|NODE_FILTER    |worker                           |Filter based on node name ex. will match 'kube-worker1'|
|CLUSTER        |MyProdCluster                    |The name given to the cluster when indexing            |
|ELASTIC_URL    |https://elastic.cotv.dk:9200     |Url for elasticsearch                                  |
|ELASTIC_USER   |elastic                          |Username for elastic, can be left blank if unprotected |
|ELASTIC_PASS   |changeme                         |Password for user                                      |

The cronjob creates a daily index in elastic called 'cluster-resources-$CLUSTER-$datetime-000001'  
It will match an index pattern like 'cluster-resources-*'

##### Project files
- cronjob.yml - Contains the configuration for running the image as a cronjob
- service-account.yml - Contains the ServiceAccount, Role and ClusterRoleBinding for the pod to access local cluster resources.
- docker-compose.yml - Used for running a local elasticsearch cluster in Docker when debugging

##### Debugging
Commands used for debugging
``` powershell
clear; $version=1.0.0; docker build -t cotv/kubernetes-resource-monitor:$version . ; docker push cotv/kubernetes-resource-monitor:$version
kubectl apply -f cronjob.yml
clear ; kubectl get cronjobs ; kubectl get jobs ; kubectl get pods
kubectl run test-debian-shell --rm -i --tty --serviceaccount=sa-cronjob-kubernetes-resource-monitor --image cotv/kubernetes-resource-monitor:1.0.0 -- bash
kubectl create secret generic secret-kubernetes-resource-monitor --from-literal=ELASTIC_USER="" --from-literal=ELASTIC_PASS=""
kubectl create secret docker-registry regcred --docker-server=<your-registry-server> --docker-username=<your-name> --docker-password=<your-pword> --docker-email=<your-email>
```