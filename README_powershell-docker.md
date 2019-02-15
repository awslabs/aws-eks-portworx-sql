
## Using this Packages

This script will do the following

1.  Create networking infrastructure required to run Kubernetes cluster
2.  Create IAM roles needed by Amazon EKS
3.  Provision a managed EKS cluster
4.  Download, install and configure kubectl tool and aws-iam-authenticator to allow an administrator to query and interact with the EKS cluster
5.  Create worker nodes and join them to the EKS cluster
6.  Create a HA Cluster of Etcd for Portworx
7.  Install Portworx and configure it for ASG and volume templates
8.  Create Portworx Storage Classes
9.  Create storage volumes needed to store SQL Server files
10. Create the deployment that runs SQL Server containers
11. Create the service that provides connectivity with the SQL Server container
12. Extract the endpoint that can be used in connection string of the SQL Server instance

### Create docker image with prerequisite tools
```
cd <this directory>
docker build . -t eks-mssql-portworx:latest
docker run -it eks-mssql-portworx:latest
```

### Configure AWS PowerShell

```
Import-Module AWSPowerShell.NetCore
Set-AWSCredential -AccessKey <AccessKey> -SecretKey <SecretKey> -StoreAs MyProfileName
Set-DefaultAWSRegion --Region us-east-1
```

### Configure AWS cli
```
PS /> aws configure
AWS Access Key ID [None]:
AWS Secret Access Key [None]:
Default region name [None]:
Default output format [json]:
```

### (Optionally) you can map in your .aws configuration

> This allows you to skip `Set-AWSCredential` and `Set-DefaultAWSRegion` from above

```
$ docker run -it -v /Path/to/.aws:/root/.aws/ eks-mssql-portworx:latest
PS /> Import-Module AWSPowerShell.NetCore
PS /> Get-AWSCredential -ListProfileDetail

ProfileName StoreTypeName         ProfileLocation
----------- -------------         ---------------
default     SharedCredentialsFile /root/.aws/credentials
```

### Test it out
```
PS />  Get-EC2Instance
GroupNames    : {}
Groups        : {}
Instances     : {kubernetes.bhavana.k8s.local-70:49:82:9e:c9:c2:bd:c6:2e:32:7f:61:97:ae:30:ad,
                kubernetes.bhavana.k8s.local-70:49:82:9e:c9:c2:bd:c6:2e:32:7f:61:97:ae:30:ad,
                kubernetes.bhavana.k8s.local-70:49:82:9e:c9:c2:bd:c6:2e:32:7f:61:97:ae:30:ad}
OwnerId       : 649513742363
RequesterId   : 940372691376
ReservationId : r-0a46ce3176d151da4

GroupNames    : {}
Groups        : {}
Instances     : {px_dev_east}
OwnerId       : 649513742363
RequesterId   :
ReservationId : r-05557ea9585d4029c
```


## Deploy the EKS Cluster

Run with default parameters
```
PS /> ./Deploy-MSSQLServerOnEKSWithPortworx.ps1 -keyName myKeyPair
```

## Run with paramater changes

Example: Set the GP2 Disk Size and Portworx Cluster Name

```
PS /> ./Deploy-MSSQLServerOnEKSWithPortworx.ps1 -keyName myKeyPair -pxGP2EBSDiskSize 50 -pxClusterName my-px-cluster
```

Example:  Set the GP2 Disk Size, Portworx Cluster Name, and provide and alternate Portworx Spec that installs the Portworx GUI.

```
PX /> ./Deploy-MSSQLServerOnEKSWithPortworx.ps1 -keyName myKeyPair -pxGP2EBSDiskSize 50 -pxClusterName my-px-cluster -pxSpecUrl https://s3.amazonaws.com/px-mssql-testing/px-spec-lh.yaml
```

> Note on the above: due to a bug (https://github.com/kubernetes/kubernetes/issues/45746) that doesnt allow ping path because there is not support in AWS annotations for LoadBalancer, you need to edit the healthcheck to use `HTTP:::/login` manually after deployment to access Portworx GUI.

![alt text](https://i.imgur.com/j2QIcMD.png)

## Deploy More SQL Servers after you ran it once.

> Make sure to use the same `-EksClusterName` parameters value.

```
./Deploy-MSSQLServerOnEKSWithPortworx.ps1 -keyName myKeyPair -pxGP2EBSDiskSize 50 -pxClusterName my-px-cluster -PVCName secondpvc -appName secondApp -SA_PasswordSecretName secondSecret -appExternalPort 1434

./Deploy-MSSQLServerOnEKSWithPortworx.ps1 -keyName myKeyPair -pxGP2EBSDiskSize 50 -pxClusterName my-px-cluster -PVCName thirdpvc -appName thirdApp -SA_PasswordSecretName thirdSecret -appExternalPort 1435

./Deploy-MSSQLServerOnEKSWithPortworx.ps1 -keyName myKeyPair -pxGP2EBSDiskSize 50 -pxClusterName my-px-cluster -PVCName fourthpvc -appName fourthApp -SA_PasswordSecretName fourthSecret -appExternalPort 1436
```

After running a few times, you can have multiples

```
root@72259ac803c1:/eks-px-mssql# ./kubectl get po   --kubeconfig /root/.kube/config-mssqlcluster
NAME                                    READY     STATUS    RESTARTS   AGE
mssql-deployment-847d68b6f4-bhjhx       1/1       Running   0          49m
secondapp-deployment-7c876c6685-9675b   1/1       Running   0          19m
thirdapp-deployment-745b4988db-8p2pv    1/1       Running   0          12m
```

Then you may connect to your SQL Server using your URL from the output and the Port you selected.

> Example connection string from RazorSQL

```
jdbc:jtds:sqlserver://<INPUTYOURURL>:1434;appName=RazorSQL;useCursors=true
jdbc:jtds:sqlserver://<INPUTYOURURL>:1435;appName=RazorSQL;useCursors=true
jdbc:jtds:sqlserver://<INPUTYOURURL>:1436;appName=RazorSQL;useCursors=true
```

If you run more than once with same parameters, it will let you know

```
Checking if SA password secret already exists...
Checking if SQL Server container deployment already exists...
Deployment thirdapp-deployment exists..
```

## Common Errors

```
Creating EKS cluster...

An error occurred (UnsupportedAvailabilityZoneException) when calling the CreateCluster operation: Cannot create cluster 'mssqlcluster' because us-east-1a, the targeted availability zone, does not currently have sufficient capacity to support the cluster. Retry and choose from these availability zones: us-east-1b, us-east-1c, us-east-1d
```

> This happens because https://amazon-eks.s3-us-west-2.amazonaws.com/cloudformation/2018-08-21/amazon-eks-vpc-sample.yaml selects first AZ for subnet.


```
./kubectl logs  mssql-deployment-677cddf7b-mt75j --kubeconfig /root/.kube/config-mssqlcluster
ERROR: Unable to set system administrator password: Password validation failed. The password does not meet SQL Server password policy requirements because it is not complex enough. The password must be at least 8 characters long and contain characters from three of the following four sets: Uppercase letters, Lowercase letters, Base 10 digits, and Symbols..
```

> Self explainitory, choose a better password. You may delete the secret `kubectl delete secrets mssql` and re-create it with a better password.


## Interacting with Portworx

(Optional) Start a new session to the Docker Container
```
▶ docker ps
CONTAINER ID        IMAGE                       COMMAND             CREATED             STATUS              PORTS               NAMES
478ba9f17438        eks-mssql-portworx:latest   "pwsh"              29 hours ago        Up 3 hours                              laughing_mclean

▶ docker exec -it 478ba9f17438 /bin/bash
root@478ba9f17438:/# cd eks-px-mssql/
```

Use KubeCTL
```
./kubectl get pods -o wide -n kube-system -l name=portworx --kubeconfig /root/.kube/config-mssqlcluster
NAME             READY     STATUS    RESTARTS   AGE       IP           NODE
portworx-4x6k7   1/1       Running   0          5m        10.0.1.216   ip-10-0-1-216.us-west-2.compute.internal
portworx-p7dlp   1/1       Running   0          5m        10.0.3.149   ip-10-0-3-149.us-west-2.compute.internal
portworx-qz7xg   1/1       Running   0          5m        10.0.2.130   ip-10-0-2-130.us-west-2.compute.internal
```

Use the Portworx Command Line
```
PX_POD=$(./kubectl get pods -l name=portworx -n kube-system --kubeconfig /root/.kube/config-mssqlcluster -o jsonpath='{.items[0].metadata.name}')

# Show Status
./kubectl exec $PX_POD -n kube-system --kubeconfig /root/.kube/config-mssqlcluster -- /opt/pwx/bin/pxctl status

# List Volumes
./kubectl exec $PX_POD -n kube-system --kubeconfig /root/.kube/config-mssqlcluster -- /opt/pwx/bin/pxctl volume list
```

## SQL Server

Find SQL Server
```
 ./kubectl get pods -l app=mssql --kubeconfig /root/.kube/config-mssqlcluster
```

Get SQL Server Endpoint
```
./kubectl get ep mssql-deployment  --kubeconfig /root/.kube/config-mssqlcluster
```

The Portworx StorageClass comes with a default snapshot internal of 70minutes. You can list snapshots available using the below commands

Find the name of the SQL Server Volume
```
root@027a9e5d6864:/eks-px-mssql# ./kubectl exec $PX_POD -n kube-system --kubeconfig /root/.kube/config-mssqlcluster -- /opt/pwx/bin/pxctl volume list
ID			NAME						SIZE	HA	SHARED	ENCRYPTED	IO_PRIORITY	STATUS		HA-STATE
913975366246141453	pvc-9bfbc4e6-b6ab-11e8-8522-0ab8d842daf2	8 GiB	3	no	no		LOW		up - attached on 10.0.2.141	Up
```

List snapshots for that parent volume

> Notice is postfix of `_periodic_2018_Sep_12_18_18`

```
root@027a9e5d6864:/eks-px-mssql# ./kubectl exec $PX_POD -n kube-system --kubeconfig /root/.kube/config-mssqlcluster -- /opt/pwx/bin/pxctl volume list -p 913975366246141453 -s
ID			NAME									SIZE	HA	SHARED	ENCRYPTED	IO_PRIORITY	STATUS		HA-STATE
357377625200315961	pvc-9bfbc4e6-b6ab-11e8-8522-0ab8d842daf2_periodic_2018_Sep_12_18_18	8 GiB	3	no	no		LOWup - detached	Detached
```

## Update Specs and Templates

Once you update specs/templates, upload them to s3.

> WARNING: Make sure the URL are updated in `$pxSpecUrl`, `$VpcTemplateUrl` and `$NodeGroupTemplateUrl` parameters.

```
aws s3 cp templates/<template> s3://<s3-bucket-location>/
aws s3 cp specs/<spec> s3://<s3-bucket-location>/
```

## Workding With SnapGroups
https://docs.portworx.com/scheduler/kubernetes/snaps-group.html 

Deploy a application used to connect to your database. Note the label used will be `mssql-group: <PVCName>`. In the default example, the PVCName is mssql-data, so the below `mssql-tools.yaml` has the same.

Deploy MSSQL Tools in a container with a volume-based workspace mounted to `/mnt`
```
./kubectl --kubeconfig /root/.kube/config-mssql-cluster create -f ./specs/mssql-tools.yaml
```

Now, list via that label.

```
./kubectl --kubeconfig /root/.kube/config-mssql-cluster get pvc -l mssql-group=mssql-data
NAME                    STATUS    VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
mssql-data              Bound     pvc-410a6930-bcdd-11e8-a293-02a822297a14   8Gi        RWO            portworx-sc    5h
mssql-tools-workspace   Bound     pvc-fd1546d5-bd0a-11e8-922a-0ab7ae22c280   1Gi        RWO            portworx-sc    57s
```

Now let's snapshot both these volumes as a Consistent SnapGroup via Portworx

```
# This consistent snapshot group will snapshot ALL
# volumes with label `mssql-group: mssql-data`
# as a consistent portworx local snapgroup
apiVersion: volumesnapshot.external-storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: mssql-snapshot-group
  namespace: default
  annotations:
    portworx/snapshot-type: local
    portworx.selector/mssql-group: mssql-data
spec:
  persistentVolumeClaimName: mssql-tools-workspace
```

Create it.

```
./kubectl --kubeconfig /root/.kube/config-mssql-cluster create -f ./specs/snapgroup.yaml
volumesnapshot.volumesnapshot.external-storage.k8s.io "mssql-snapshot-group" created
```

Let's list the snapshot groups now.
```
 ./kubectl --kubeconfig /root/.kube/config-mssql-cluster get volumesnapshot
NAME                                                                              AGE
mssql-snapshot-group                                                              31s
mssql-snapshot-group-mssql-data-e59efd66-bd0b-11e8-922a-0ab7ae22c280              27s
mssql-snapshot-group-mssql-tools-workspace-e59efd66-bd0b-11e8-922a-0ab7ae22c280   28s
```

Then, to use thes snapshots, you would create new PVC from these snapshots and use them for your apps to restore. To do this, you can follow these instructions: https://docs.portworx.com/scheduler/kubernetes/snaps-local.html#pvc-from-snap 

# TODO

 - (DONE) Allow of IO1 or GP2 or Both
 - (DONE) Support ASG Best Practices for Portworx
 - (DONE) Provide High and Low IO StorageClass's with Portworx
 - (DONE) Provide Snapsshot Schedule Interval Setting for Portworx PVCs
 - (DONE) Add Snapshot Policy for MSSQL volume(s)
 	- Default is every 70 minutes and can be changed via parameter
 - (DONE) Make Etcd a 3 node HA over AZs.
 	- Uses etcd-operator and is HA in top of Kubernetes itself and spread across AZs in Worker ASG
 - (DONE) Make Etcd nodes auto-heal using ASG.
 	- Uses etcd-operator and is HA in top of Kubernetes itself, Kubernetes will auto-heal the etcd nodes.
 - (STARTED) Add Example for 3DSnaps. (can be in a separate script file. Ideally in the form of a PowerShell cmdlet)
 - (TODO) Add Journal Device for PX (tracking issue: https://portworx.atlassian.net/browse/PWX-6289)
 - (TODO) Add example of using etcd backup operator 
   - https://github.com/coreos/etcd-operator/blob/master/doc/user/walkthrough/backup-operator.md 
 - (TODO) Add example of using etcd restore operator 
   - https://github.com/coreos/etcd-operator/blob/master/doc/user/walkthrough/restore-operator.md
 - (TODO) Add Example of Volume Import (from SQLServer on Native EBS)
 - (In Progress) Add Example of using SnapGroups (can be in a separate script file. Ideally in the form of a PowerShell cmdlet)
   - (DONE) Example and specs
   - (TODO) CmdLet integration
 - (TODO) integrate using optional seperate etcd template instead of etcd-operator
 - (TODO) provide README on how to deploy templates and use CLI without powershell script (to help with QuickStart)
 	- [quickstart deployment guide](files/Portworx_MSSQL_DeploymenyGuide_2018.docx)
- (TODO) Include testing and outputes
	- https://aws-quickstart.github.io/testing.html 
	- TaskCat
- (TODO) check for requirement before start the script, like keypairs, right region setup
- (TODO) clarfiy that if you want to connect to multiple clusters you can not do it from the kubectl in the same folder. 
- (TODO) check the saved PS credentials vs the IAM role since first time only the owner of the EKS cluster can connect to it. basically making sure the same credentials for both CLI and PS is used. 
