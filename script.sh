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

### Pod Statuses ################################
podStatuses=$(kubectl get pods --all-namespaces -o=jsonpath="{range .items[*]}{.metadata.namespace};{.metadata.name};{.status.containerStatuses[0].ready};{.status.containerStatuses[0].restartCount};{.status.containerStatuses[0].started};{.status.phase}{'\n'}{end}")

### Deployment Statuses #########################
deploymentStatuses=$(kubectl get deployments --all-namespaces -o=jsonpath="{range .items[*]}{.metadata.namespace};{.metadata.name};{.status.availableReplicas};{.status.readyReplicas};{.status.replicas};{.status.updatedReplicas};{.status.unavailableReplicas}{'\n'}{end}")

### Post data ###################################
curl -k -X POST -u $elasticuser:$elasticpass -H "Content-Type: application/json" "$elasticurl/$indexname/_doc" -d '
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

for str in ${podStatuses// / } ; do
    IFS=';' read -ra value <<< "$str"
    curl -k -X POST -u $elasticuser:$elasticpass -H "Content-Type: application/json" "$elasticurl/$indexname/_doc" -d '
    {"timestamp":"'"$(date +%Y-%m-%dT%H:%M:%S)"'","cluster":"'$cluster'","namespace":"'${value[0]}'","podstatus.podName":"'${value[1]}'","podstatus.containerStatus":"'${value[2]}'","podstatus.restartCount":'${value[3]}',"podstatus.started":"'${value[4]}'","podstatus.phase":"'${value[5]}'"}'
done

for str in ${deploymentStatuses// / } ; do
    IFS=';' read -ra value <<< "$str"
    availableReplicas="null"
    readyReplicas="null"
    unavailableReplicas="null"
    # Set availableReplicas to 0 if it doesn't exist
    if [ -z "${value[2]}" ]
    then
        echo "\$availableReplicas is NULL setting to 0"
        availableReplicas="0"
    else
        availableReplicas="${value[2]}"
    fi
    # Set readyReplicas to 0 if it doesn't exist
    if [ -z "${value[3]}" ]
    then
        echo "\$readyReplicas is NULL setting to 0"
        readyReplicas="0"
    else
        readyReplicas="${value[3]}"
    fi
    # Set unavailableReplicas to 0 if it doesn't exist
    if [ -z "${value[6]}" ]
    then
        echo "\$unavailableReplicas is NULL setting to 0"
        unavailableReplicas="0"
    else
        unavailableReplicas="${value[6]}"
    fi
    curl -k -X POST -u $elasticuser:$elasticpass -H "Content-Type: application/json" "$elasticurl/$indexname/_doc" -d '
    {"timestamp":"'"$(date +%Y-%m-%dT%H:%M:%S)"'","cluster":"'$cluster'","namespace":"'${value[0]}'","depstatus.deploymentName":"'${value[1]}'","depstatus.availableReplicas":'${availableReplicas}',"depstatus.readyReplicas":'${readyReplicas}',"depstatus.replicas":'${value[4]}',"depstatus.updatedReplicas":'${value[5]}',"depstatus.unavailableReplicas":'${unavailableReplicas}'}'
done
