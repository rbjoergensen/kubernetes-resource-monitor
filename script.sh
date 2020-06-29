#!/bin/bash

### Variables ###################################
# for a node called k8s-00-predev-wor1 use a filter like '-wor' or 'k8s-00-predev-wor' or set to null to have no filter
nodefilter=$NODE_FILTER
cluster=$CLUSTER
elasticurl=$ELASTIC_URL
indexdate=$(date +"%Y.%m.%d")
indexname="cluster-resources-$cluster-$indexdate-000001"
elasticuser=$ELASTIC_USER
elasticpass=$ELASTIC_PASS

if [ -z $NODE_FILTER ] || [ -< $CLUSTER ] || [ -< $ELASTIC_URL ]
then
      exit 1
fi
if [ -z $ELASTIC_USER ] || [ -< $ELASTIC_PASS ]
then
      echo "Elastic credentials have not been set, if elastic has password protection the job will fail"
fi

### Requests ####################################
# Get requsted cpu in milli-cpu(m)
requested_cpu=$(kubectl get po --all-namespaces -o=jsonpath="{range .items[*]}{.spec.nodeName}{range .spec.containers[*]}  {.resources.requests.cpu}{'\n'}{end}{'\n'}{end}" | 
    awk '/'$nodefilter'/' | awk {'print $2'} | awk NF | sed 's/[^0-9]*//g' | awk '{s+=$1} END {print s}')
# Get requested mem in mb(M)
requested_mem=$(kubectl get po --all-namespaces -o=jsonpath="{range .items[*]}{.spec.nodeName}{range .spec.containers[*]}  {.resources.requests.memory}{'\n'}{end}{'\n'}{end}" | 
    awk '/'$nodefilter'/' | awk {'print $2'} | awk NF | sed 's/[^0-9]*//g' | awk '{s+=$1} END {print s}')
# Get allocated pod count
allocated_pods=$(kubectl get pod -o=custom-columns=NODE:.spec.nodeName --all-namespaces | grep $nodefilter | wc -l)

### Capacity ####################################
# Get the total cpu capacity of all worker nodes
capacity_cpu=$(kubectl get no -o json | jq -r '.items | sort_by(.status.capacity.cpu)[]|[.metadata.name,.status.capacity.cpu]| @tsv' |
    awk '/'$nodefilter'/' | awk {'print $2'} | sed 's/[^0-9]*//g' | awk '{print $1*1000}' | awk '{print int($1)}' | awk '{s+=$1} END {print s}')
# Get the total memory capacity of all worker nodes
capacity_mem=$(kubectl get no -o json | jq -r '.items | sort_by(.status.capacity.memory)[]|[.metadata.name,.status.capacity.memory]| @tsv' |
    awk '/'$nodefilter'/' | awk {'print $2'} | sed 's/[^0-9]*//g' | awk '{print $1/1024}' | awk '{print int($1)}' | awk '{s+=$1} END {print s}')
capacity_pods=$(kubectl get no -o json | jq -r '.items | sort_by(.status.capacity.pods)[]|[.metadata.name,.status.capacity.pods]| @tsv' | 
    awk '/'$nodefilter'/' | awk '{print int($2)}' | awk '{s+=$1} END {print s}')

### Percentages #################################
# Calculate cpu requests in percent of capacity
requested_cpu_percent=$(awk "BEGIN {printf \"%.2f\n\", ($requested_cpu/$capacity_cpu)*100}")
# Calculate mem requests in percent of capacity
requested_mem_percent=$(awk "BEGIN {printf \"%.2f\n\", ($requested_mem/$capacity_mem)*100}")
# Calculate allocated pods in percent of capacity
allocated_pods_percent=$(awk "BEGIN {printf \"%.2f\n\", ($allocated_pods/$capacity_pods)*100}")

### Post data ###################################
curl -X --insecure POST -u $elasticuser:$elasticpass -H "Content-Type: application/json" "$elasticurl/$indexname/_doc" -d '
{
    "timestamp":"'"$(date +%Y-%m-%dT%H:%M:%S)"'",
    "cluster":"'$cluster'",
    "requests.cpu":'$requested_cpu',
    "requests.mem":'$requested_mem',
    "requests.pods":'$allocated_pods',
    "capacity.cpu":'$capacity_cpu',
    "capacity.mem":'$capacity_mem',
    "capacity.pods":'$capacity_pods',
    "requests.cpu-percent":'$requested_cpu_percent',
    "requests.mem-percent":'$requested_mem_percent',
    "allocated.pods-percent":'$allocated_pods_percent'
}'
