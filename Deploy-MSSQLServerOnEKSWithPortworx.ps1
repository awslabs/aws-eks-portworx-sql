<#Copyright 2018 Amazon.com, Inc. or its affiliates. All Rights Reserved.
  
  Licensed under the Apache License, Version 2.0 (the "License").
  You may not use this file except in compliance with the License.
  A copy of the License is located at
  
      http://www.apache.org/licenses/LICENSE-2.0
  
  or in the "license" file accompanying this file. This file is distributed 
  on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either 
  express or implied. See the License for the specific language governing 
  permissions and limitations under the License.#>

<#

.NOTES
Authors: 
          Sepehr Samiei
          Ryan Wallner

.SYNOPSIS
This script deploys SQL Server on Amazon EKS.

.DESCRIPTION
This script perfoms following actions:

1- Create networking infrastructure required to run Kubernetes cluster
2- Create IAM roles needed by Amazon EKS
3- Provision a managed EKS cluster
4- Download, install and configure kubectl tool and aws-iam-authenticator to allow an administrator to query and interact with the EKS cluster
5- Create worker nodes and join them to the EKS cluster
6- Install Portworx and configure it for ASG and volume templates
7- Create Portworx Storage Class
8- Create storage volumes needed to store SQL Server files
9- Create the deployment that runs SQL Server containers
10- Create the service that provides connectivity with the SQL Server container
11- Extract the endpoint that can be used in connection string of the SQL Server instance

.EXAMPLE
./Deploy-MSSQLServerOnEKSWithPortworx.ps1 -keyName myKeyPair 

This will deploy create a VPC, the EKS cluster, all the worker nodes, Portworx clustered storage, and deploys SQL Server on top of those. If any of the resources already exists, it will be reused.

.EXAMPLE
./Deploy-MSSQLServerOnEKSWithPortworx.ps1 -keyName myKeyPair -appName sql2 

If you want to deploy multiple SQL Server instances, you have to supply additional parameters with exclusive values for each deployment.

.EXAMPLE
./Deploy-MSSQLServerOnEKSWithPortworx.ps1 -keyName myKeyPair -appName sql2 -VpcId vpc-4ff3cc2b -SubnetIds @("subnet-52def80b","subnet-4dfc0704") -SG sg-f332a395

This will deploy SQL Server in an existing VPC. You have to make sure required ports are opened in your AWS Security Group.

.LINK

.PARAMETER VpcTemplateUrl
CloudFormation template used to create the Virtual Private Cloud (VPC) of the worker nodes. Ultimately SQL Server instance will be deployed and accessible in this VPC. 
Default value is "https://s3.amazonaws.com/px-mssql-testing/eks-px-mssql-vpc.yaml"

.PARAMETER NodeGroupTemplateUrl
CloudFormation template used to create the worker nodes. SQL Server will run inside a container that is scheduled on one of these worker nodes. 
Default value is "https://s3.amazonaws.com/px-mssql-testing/eks-px-mssql-nodegroup.yaml"

.PARAMETER EksClusterTemplateUrl 
CloudFormation template used to create the EKS cluster and role.
Default value is "https://s3-ap-southeast-2.amazonaws.com/ss-experiments/eks-cluster.template"

.PARAMETER ClusterVPCStackName
CloudFormation stack name of the cluster VPC.
Default value is "EKSClusterVPC-MSSQLPX"

.PARAMETER WorkerNodesStackName
CloudFormation stack name of the worker nodes.
Default value is "EKSWorkerNodes-MSSQLPX"

.PARAMETER StackCreationTimeout
The time CloudFormation will wait for a stack creation process to complete.
Default value is "1800"

.PARAMETER VpcBlock
The CIDR block of the cluster VPC.
Default value is "10.0.0.0/16"

.PARAMETER Subnet01Block
The CIDR block of the first subnet in cluster VPC.
Default value is "10.0.1.0/24"

.PARAMETER Subnet02Block
The CIDR block of the second subnet in cluster VPC.
Default value is "10.0.2.0/24"

.PARAMETER Subnet03Block
The CIDR block of the third subnet in cluster VPC.
Default value is "10.0.3.0/24"

.PARAMETER VpcId
ID of an existing VPC. If you don't supply this parameter, the script will use following parameters to create a new VPC. 
VpcTemplateUrl
ClusterVPCStackName
VpcBlock
Subnet01Block
Subnet02Block
Subnet03Block

If you supply a value for this parameter, those parameters will be ignored.

.PARAMETER SubnetIds
A string array containing subnet Id values of existing subnets within specified VPC. This parameter is used with VpcId.

.PARAMETER SG
ID of an existing Security Group within the specified VPC. This parameter is used with VpcId.

.PARAMETER EksClusterStackName 
Name of the CloudFormation template containing EKS cluster.
Default value is "mssql-eks-cluster"

.PARAMETER EksClusterName
Name of the managed EKS cluster.
Default value is "mssqlcluster"

.PARAMETER UseExistingEksCluster 
If set to true, will try to use an existing EKS cluster with the name specified in EksClusterName. If set to false, uses the CFN stack.
Default value is false

.PARAMETER NodeGroupName
Name of the AWS EC2 AutoScaling Group through which worker nodes will be deployed.
Default value is "mssqlclusternodegroup"

.PARAMETER NodeASGroupMin
Minimum number of worker nodes that should be maintained by the AutoScaling group
Default value is 2

.PARAMETER NodeASGroupMax
Maximum number of worker nodes that should be maintained by the AutoScaling group
Default value is 3

.PARAMETER WorkerInstanceType
EC2 instance type that should be used by AutoScaling group to create worker nodes.
Default value "m4.xlarge"

.PARAMETER gpuOptimization
Boolean value indicating whether worker nodes should be deployed using a GPU optimized AMI. GPU optimization is not required by SQL Server. Set to $true if you want to use the cluster for other applications.
Default value is false

.PARAMETER keyName
Name of an existing key pair in your target region. You will need this key pair if you want to login to worker node EC2 instances created by this script.

.PARAMETER Region
Target AWS region where the cluster should be deployed. This should be an AWS region where Amazon EKS service is available.
Default value is "us-west-2"

.PARAMETER bootstrapArgs
Any arguments that should be passed to new worker nodes at bootstrap time.
Default value is ""

.PARAMETER SA_PasswordSecretName
Name of the secret object containing mssql SA password. This is not the password itself, but a label that allows K8s to retrieve the actual password.
Default value is "mssql"

.PARAMETER PVCNameSuffix
The suffix that will be appended to the Persistent Volume Claim used to store SQL Server files. If you want to deploy multiple instances of SQL Server in your cluster, you should make sure PVC name for each instance is unique.
Default value is "-data"

.PARAMETER PVCName
The Persistent Volume Claim name used to store SQL Server files. If you don't provide an explicit name, this script will use the appName appended with PVCNameSuffix. If you want to deploy multiple instances of SQL Server in your cluster, you should make sure PVC name for each instance is unique.
Default value is null

.PARAMETER useNlb
If set to True, will use a Network Load Balancer for K8s Service. If set to False, will use a classic Elastic Load Balancer.
Default value is null

.PARAMETER MSSQL_PID
Specifies which edition of SQL Server should be used.
Developer and Express editions are free. Enterprise and Standard editions require licenses and can be used in production. For more details, please refer to Microsoft Use Rights and licensing.
Default value is Developer.

.PARAMETER appName
Application name used by K8s deployment and service to identify SQL Server container. If you intend to deploy multiple instances of SQL Server in the same cluster, you should provide different appName values for each deployment.
Default value is mssql.

.PARAMETER appExternalPort
The Loadbalancer port from outside of the EKS cluster to access SQL Server
Default value is 1433

.PARAMETER minCpu
The minimum amount of CPU resource assigned to SQL Server. This is used tp assign the Request parameter in K8s.
Default value is 4.

.PARAMETER maxCpu
The maximum amount of CPU resource assigned to SQL Server. This is used tp assign the Limit parameter in K8s. If SQL Server needs more CPU, and more idle CPU is available, it will be allowed to burst up to the number of CPU resources defined by this parameter. This number should be used as the number of cores in a virtual OSE. For more details, please see Microsoft Use Rights and licensing.
Default value is 8.

.PARAMETER persistentVolumeClaimSize
The Persistent Volume Claim Size that SQL Server will use inside the container
Default value is 8Gi.

.PARAMETER pxSpecUrl
The URL of the Portworx spec template.
Default value is "https://s3.amazonaws.com/px-mssql-testing/px-spec.yaml".

.PARAMETER pxClusterName
Name of the Portworx clustered storage.
Default value is "px-eks-cluster-01".

.PARAMETER pxStorageClassName
Name of the Portworx storage class for SQL Server to use. Two are available ("portworx-sc" for normal IO and "high-portworx-sc" for high IO)
Default value is "portworx-sc".

.PARAMETER pxEtcdPort
Port number of the ETCD service, used by Portworx.
Default value is 2379.

.PARAMETER pxEKSVersion
The version of EKS, Portworx uses this in its DaemonSet
Default value is 1.10.3.

.PARAMETER pxPvcSnapshotInterval
The periodic snapshot interval for the Portworx Storage Classes in (Minutes)
Default value is 70

.PARAMETER pxGP2EBSDiskSize 
The GP2 EBS disk size (in GB) that Portworx will consume for clustered storage. (Leave $null to not use GP2)
Default value is 100

.PARAMETER pxIO1EBSDiskSize
The IO1 EBS disk size (in GB) that Portworx will consume for clustered storage. (Leave $null to not use IO1)
Default value is $null

.PARAMETER pxIO1EBSDiskIOPS
The IO1 EBS disk that will be used with the IO1 EBS disk for Portworx (Mandetory if using IO1 disks)
Default value is $null

.PARAMETER pxStorageNodesPerAz
The amount of Storage Providing nodes per AZ in and ASG. PX Must have 3 nodes. Examples (set to 1 if 3 AZs) and (2 if 2 AZ etc.)
Default value is 1

.PARAMETER internalService
Specified whether the SQL Server instance should be internally accessible inside the VPC. If set to True, it will create an internal load balancer. If set to False, it will create an internet-facing load balancer.
Default value is False.

#>

param (
    [string] $EKSRoleName = "EKSRole",
    [string] $VpcTemplateUrl = "https://s3.amazonaws.com/px-mssql-testing/eks-px-mssql-vpc.yaml",
    [string] $NodeGroupTemplateUrl = "https://s3.amazonaws.com/px-mssql-testing/eks-px-mssql-nodegroup.yaml",
    [string] $EksClusterTemplateUrl = "https://s3-ap-southeast-2.amazonaws.com/ss-experiments/eks-cluster.template", 
    [string] $ClusterVPCStackName = "EKSClusterVPC-MSSQLPX",
    [string] $WorkerNodesStackName = "EKSWorkerNodes-MSSQLPX",
    [string] $StackCreationTimeout = "1800",
    [string] $VpcBlock = "10.0.0.0/16",
    [string] $Subnet01Block = "10.0.1.0/24",
    [string] $Subnet02Block = "10.0.2.0/24",
    [string] $Subnet03Block = "10.0.3.0/24",
    [string] $VpcId,
    [string] $SubnetIds,
    [string] $SG,
	[string] $EksClusterStackName = "mssql-eks-cluster", 
    [string] $EksClusterName = "mssql-cluster",
	[bool] $UseExistingEksCluster = $false,
    [string] $NodeGroupName = "mssqlclusternodegroup",
    [string] $NodeASGroupMin = "3",
    [string] $NodeASGroupMax = "3",
    [string] $WorkerInstanceType = "m5.2xlarge",
    [bool] $gpuOptimization = $false,
    [Parameter(Mandatory=$true,HelpMessage="Enter the name of an existing key pair in your target region. You will need this key pair if you want to login to worker node EC2 instances.")]
    [string] $keyName,
    [string] $Region = "us-west-2",
    [string] $bootstrapArgs = "",
    [string] $SA_PasswordSecretName = "mssql",
    [string] $PVCNameSuffix = "-data",
    [string] $PVCName = $null,
    [bool] $useNlb = $false,
    [string] $MSSQL_PID = "Developer",
    [string] $appName = "mssql",
    [string] $appExternalPort = "1433",
    [string] $minCpu = "4",
    [string] $maxCpu = "8",
    [string] $persistentVolumeClaimSize = "8Gi",
    [string] $pxSpecUrl = "https://s3.amazonaws.com/px-mssql-testing/px-spec.yaml",
    [string] $pxClusterName = "px-eks-cluster-01",
    [string] $pxStorageClassName = "portworx-sc",
    [string] $pxEKSVersion = "1.10.3",
    [string] $pxPvcSnapshotInterval = "70",
    [string] $pxGP2EBSDiskSize = "100",
    [string] $pxIO1EBSDiskSize = $null,
    [string] $pxIO1EBSDiskIOPS = $null,
    [string] $pxStorageNodesPerAz = "1",
	  [bool] $internalService = $false
)

$appName = $appName.ToLower()
$deploymentName = "{0}-deployment" -f $appName
if ([Environment]::OSVersion.Platform -eq "Unix")
{
    $PSOnLinux = $true
}
else
{
    $PSOnLinux = $false
}
$dirChar = "\"
$wrongDirChar = "/"
if ($PSOnLinux -eq $true)
{
	$dirChar = "/"
    $wrongDirChar = "\"
}
#region Functions
function GetFilePathInPSScriptRoot($fileName)
{
	$path = "$PSScriptRoot{0}$fileName" -f $dirChar
    return $path
}

If ($PSOnLinux -eq $true) {
  $kubectlPath = GetFilePathInPSScriptRoot("kubectl")
  }  Else {
  $kubectlPath = GetFilePathInPSScriptRoot("kubectl.exe")
} 
function KubectlCmd($p1, $p2)
{
    $result = Invoke-Expression "$kubectlPath $p1 $p2"
    return $result
}
function KubectlApply($yamlFilePath)
{
    $result = ""
    if ($yamlFilePath.StartsWith("https://") -or $yamlFilePath.StartsWith("http://") -or ($yamlFilePath.StartsWith($PSScriptRoot) -and !$yamlFilePath.Contains($wrongDirChar)))
    {
        $result = KubectlCmd -p1 "apply -f" -p2 $yamlFilePath
    }
    elseif ($yamlFilePath.Contains($wrongDirChar))
    {
        $str = $yamlFilePath.Replace($wrongDirChar, $dirChar)
        $result = KubectlApply($str)
    }
    else
    {
        $filePath = GetFilePathInPSScriptRoot($yamlFilePath)
        $result = KubectlCmd -p1 "apply -f" -p2  $filePath
    }
    return $result;
}
function KubectlDescribe($p)
{
    $result = KubectlCmd -p1 "describe" -p2 $p
    return $result
}
function KubectlCreate($p)
{
    $result = KubectlCmd -p1 "create" -p2 $p
    return $result
}
function KubectlGet($p)
{
    $result = KubectlCmd -p1 "get" -p2 $p
    return $result
}
function KubectlPatch($p)
{
    $result = KubectlCmd -p1 "patch" -p2 $p
    return $result
}
function ConvertFromCliJson($cliJson)
{
    $sb = [System.Text.StringBuilder]::new()
    $cliJson.forEach{
        $sb.Append($_)
    }
    $svcObj = ConvertFrom-Json($sb.ToString())
    return $svcObj
}
function GetUniqueIdWithName($nameString)
{
    $date = Get-Date -UFormat "%Y-%m-%d"
    $guid = New-Guid
    $uniqueName = "$nameString-$guid-$date"
    return $uniqueName
}
function WaitUntillReady($message, $kubeGetCmd, $expectedStatus)
{
    $status = ""
    while ($status -ne $expectedStatus)
    {
        Write-Host $message -ForegroundColor Cyan
        Start-Sleep -Seconds 10
        $statusList = KubectlGet($kubeGetCmd)
        for ($c = 1; $c -lt $statusList.Length; $c++)
        {
            $status = $statusList[$c]
            while ($status.Contains("  "))
            {
                $status = $status.Replace("  ", " ")
            }
            $status = $status.Split(' ')
            $status = $status[1]
            Write-Host $statusList[$c] -ForegroundColor Cyan
            if ($status -ne $expectedStatus)
            {
                break;
            }
        }
    }
}
function CreateCfnStack($stackName, $templateUrl, $parameters, $capability)
{
    $CfnStack = $null
    $CfnStackList = Get-CfnStack -Region $Region
    $CfnStackList.forEach{
        if ($_.StackName -eq $stackName)
        {
            $CfnStack = $_
            return $CfnStack;
        }
    }
    #$CfnStack = Get-CfnStack -StackName $stackName -Region $Region
    if ($CfnStack -eq $null)
    {
        Write-Host "Creating $stackName CloudFormation stack ..." -ForegroundColor Cyan
        New-CfnStack -StackName $stackName `
                     -TemplateURL $templateUrl `
                     -Capability $capability `
                     -Parameter $parameters `
                    -Region $Region
        $CfnStack = Wait-CfnStack -StackName $stackName -Timeout $StackCreationTimeout -Status CREATE_COMPLETE -Region $Region
    }
    elseif ($CfnStack.StackStatus -eq "CREATE_IN_PROGRESS" -or $CfnStack.StackStatus -eq "UPDATE_IN_PROGRESS")
    {
        Write-Host "Waiting for $stackName CloudFormation stack creation to complete..." -ForegroundColor Cyan
        $CfnStack = Wait-CfnStack -StackName $stackName -Timeout $StackCreationTimeout -Status CREATE_COMPLETE -Region $Region
    }
    if ($CfnStack.StackStatus -ne "CREATE_COMPLETE")
    {
        Write-Host "Creating $stackName CloudFormation stack failed. Terminating deployment." -ForegroundColor Red
        exit 1
    }
    
    $outputs = $CfnStack.Outputs
    return $outputs
}
#endregion

#region Create EKS cluster VPC
Write-Host "Checking if EKS cluster VPC stack already exists..." -ForegroundColor Cyan
if ([System.String]::IsNullOrWhiteSpace($VpcId))
{
    $ClusteVPCStackOutputs = CreateCfnStack -stackName $ClusterVPCStackName -templateUrl $VpcTemplateUrl -parameters `
            @( @{ ParameterKey="VpcBlock"; ParameterValue=$VpcBlock }, `
            @{ ParameterKey="Subnet01Block"; ParameterValue=$Subnet01Block }, `
            @{ ParameterKey="Subnet02Block"; ParameterValue=$Subnet02Block }, `
            @{ ParameterKey="Subnet03Block"; ParameterValue=$Subnet03Block } )
    foreach ($output in $ClusteVPCStackOutputs)
    {
        switch ($output.OutputKey)
        {
            SecurityGroups {
                $SG = $output.OutputValue
            }
            VpcId {
                $VpcId = $output.OutputValue
            }
            SubnetIds {
                $SubnetIds = $output.OutputValue
            }
        }
    }
}
else
{
    try
    {
        Get-EC2Vpc -VpcId $VpcId -Region $Region
        Get-EC2SecurityGroup -GroupId $SG -Region $Region
        $tempSubnets = $SubnetIds.trim().Split(',')
        $SubnetIds = [System.String]::Empty

        foreach ($subnet in $tempSubnets)
        {
            Get-EC2Subnet -SubnetId $subnet -Region $Region
            $comma = [System.String]::Empty
            if (![System.String]::IsNullOrEmpty($SubnetIds))
            {
                $comma = ','
            }
            $SubnetIds = "{0}{1}{2}" -f $SubnetIds, $comma, $subnet
        }
    }
    catch
    {
        Write-Host $_.Exception.Message
        Write-Host "Provided VPC ID, SubnetIds or Security group, does not exist. Terminating the script." -ForegroundColor Red
        exit 1
    }
}
#endregion

#region Install kubectl for EKS

If ($PSOnLinux -eq $true) {
  $kubectlUrl = "https://amazon-eks.s3-us-west-2.amazonaws.com/1.10.3/2018-07-26/bin/linux/amd64/kubectl"
  }  Else {
  $kubectlUrl = "https://amazon-eks.s3-us-west-2.amazonaws.com/1.10.3/2018-07-26/bin/windows/amd64/kubectl.exe"
} 
if (![System.IO.File]::Exists($kubectlPath))
{
    Write-Host "Downloading kubectl..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $kubectlUrl -OutFile $kubectlPath
}

If ($PSOnLinux -eq $true) {
   Invoke-Expression "chmod +x $PSScriptRoot/kubectl"
}   
Invoke-Expression "$kubectlPath version --short --client"
#endregion

#region Install aws-iam-authenticator for EKS

If ($PSOnLinux -eq $true) {
  $authenticatorUrl = "https://amazon-eks.s3-us-west-2.amazonaws.com/1.10.3/2018-07-26/bin/linux/amd64/aws-iam-authenticator"
  $authenticatorlPath = GetFilePathInPSScriptRoot("aws-iam-authenticator")
  }  Else {
  $authenticatorUrl = "https://amazon-eks.s3-us-west-2.amazonaws.com/1.10.3/2018-07-26/bin/windows/amd64/aws-iam-authenticator.exe"
  $authenticatorlPath = GetFilePathInPSScriptRoot("aws-iam-authenticator.exe")
} 

if (![System.IO.File]::Exists($authenticatorlPath))
{
    Write-Host "Downloading aws-iam-authenticator..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $authenticatorUrl -OutFile $authenticatorlPath
}
If ($PSOnLinux -eq $true) {
   Invoke-Expression "chmod +x $PSScriptRoot/aws-iam-authenticator" 
   Invoke-Expression "cp $PSScriptRoot/aws-iam-authenticator /usr/bin/"
} 
Invoke-Expression "$authenticatorlPath help"
#endregion

#region Create EKS cluster
Write-Host "Checking if EKS cluster already exists..." -ForegroundColor Cyan
if ($UseExistingEksCluster -eq $false)
{
    $EksClusterStackOutputs = CreateCfnStack -stackName $EksClusterStackName -templateUrl $EksClusterTemplateUrl -capability "CAPABILITY_IAM" -parameters `
            @( @{ ParameterKey="SecurityGroupID"; ParameterValue=$SG }, `
            @{ ParameterKey="SubnetIDs"; ParameterValue=$SubnetIds }, `
            @{ ParameterKey="VPCID"; ParameterValue=$VpcId }, `
            @{ ParameterKey="ClusterName"; ParameterValue=$EksClusterName } )
    foreach ($output in $EksClusterStackOutputs)
    {
        switch ($output.OutputKey)
        {
            EKSClusterEndpoint {
                $EksEndpoint = $output.OutputValue
            }
            EKSClusterCertificate {
                $EksCertificate = $output.OutputValue
            }
        }
    }
}
else
{
    $ClusterListCmd = "aws eks list-clusters --region {0} --output text" -f $Region
    $ClusterStatusCheckCmd = "aws eks describe-cluster --name {0} --query cluster.status --region {1}" -f $EksClusterName, $Region
    $clusterStatus = Invoke-Expression $ClusterListCmd
    Write-Host $clusterStatus
    if ($clusterStatus -ne $null)
    {
        foreach ($cluster in $clusterStatus)
        {
            if ($cluster.Contains($EksClusterName))
            {
                $clusterStatus = "found"
                break;
            }
        }
    }
    if ($clusterStatus -eq $null -or $clusterStatus -ne "found")
    {
        Write-Host "Provided EKS cluster does not exist. Terminating." -ForegroundColor Red
        exit 1
    }
    else
    {    
        Write-Host "Found existing EKS cluster. Checking for status..." -ForegroundColor Cyan
        $clusterStatus = Invoke-Expression $ClusterStatusCheckCmd
    }
    while ($clusterStatus -ne "`"ACTIVE`"")
    {
        Write-Host "Waiting for cluster status active..." -ForegroundColor Cyan
        Start-Sleep -Seconds 30    
        $clusterStatus = Invoke-Expression $ClusterStatusCheckCmd
        Write-Host $clusterStatus
    }

    Write-Host "Retrieving EKS cluster endpoint and certificate..." -ForegroundColor Cyan
    $retrieveEndpointCmd = "aws eks describe-cluster --name {0}  --query cluster.endpoint --output text --region {1}" -f $EksClusterName, $Region
    $retrieveCertCmd = "aws eks describe-cluster --name {0}  --query cluster.certificateAuthority.data --output text --region {1}" -f $EksClusterName, $Region
    $EksEndpoint = Invoke-Expression $retrieveEndpointCmd
    $EksCertificate = Invoke-Expression $retrieveCertCmd
}
#endregion

#region Configure kubectl for Amazon EKS
Write-Host "Configuring kubectl for Amazon EKS..." -ForegroundColor Cyan
$identity = Get-STSCallerIdentity
Write-Host "Kubectl is connecting to EKS using this identity:"
Write-Host $identity.Arn

$kubedir = "{0}{1}.kube" -f $HOME, $dirChar
if (![System.IO.Directory]::Exists($kubedir))
{
    [System.IO.Directory]::CreateDirectory($kubedir)
}

$configFileContent = "apiVersion: v1
clusters:
- cluster:
    server: "+ $EksEndpoint + "
    certificate-authority-data: " + $EksCertificate + "
  name: kubernetes
contexts:
- context:
    cluster: kubernetes
    user: aws
  name: aws
current-context: aws
kind: Config
preferences: {}
users:
- name: aws
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1alpha1
      command: aws-iam-authenticator
      args:
        - `"token`"
        - `"-i`"
        - `"" + $EksClusterName + "`"
        # - `"-r`"
        # - `"<role-arn>`"
      # env:
        # - name: AWS_PROFILE
        #   value: `"<aws-profile>`""

$configFilePath = "{0}{1}config-{2}" -f $kubedir, $dirChar, $EksClusterName
Set-Content -Path $configFilePath -Value $configFileContent -Force

if ($env:KUBECONFIG -eq $null -or !$env:KUBECONFIG.Contains($configFilePath))
{
    [System.Environment]::SetEnvironmentVariable("KUBECONFIG", "$env:KUBECONFIG:$configFilePath", [System.EnvironmentVariableTarget]::User)
    $env:KUBECONFIG = "$env:KUBECONFIG:$configFilePath"
}
$TestKubectl = KubectlGet("services")
#endregion

#region Launch and configure Amazon EKS worker nodes
Write-Host "Launching and configuring Amazon EKS worker nodes..." -ForegroundColor Cyan
Write-Host "retrieving updated list of EKS optimized AMIs in target region..." -ForegroundColor Cyan
$name_values = New-Object 'collections.generic.list[string]' 
$workerNodeFilter = "amazon-eks-node*"
if ($gpuOptimization -eq $true)
{
    Write-Host "Using GPU optimized AMI. Notice, you may need to go to AWS marketplace and accept use terms. Otherwise instance creation may fail, ultimately forcing stack creation to fail too."
    $workerNodeFilter = "amazon-eks-gpu-node*"
}
$name_values.add($workerNodeFilter) 
$filter_platform = New-Object Amazon.EC2.Model.Filter -Property @{Name = "name"; Values = $name_values} 
$amiList = (Get-EC2Image -Filter $filter_platform -Region $Region | Sort-Object -Property "CreationDate" -Descending)

$WorkerNodesStackOutputs = CreateCfnStack -stackName $WorkerNodesStackName -templateUrl $NodeGroupTemplateUrl -capability "CAPABILITY_IAM" -parameters `
        @( @{ ParameterKey="ClusterName"; ParameterValue=$EksClusterName }, `
        @{ ParameterKey="ClusterControlPlaneSecurityGroup"; ParameterValue=$SG }, `
        @{ ParameterKey="NodeGroupName"; ParameterValue=$NodeGroupName }, `
        @{ ParameterKey="NodeAutoScalingGroupMinSize"; ParameterValue=$NodeASGroupMin }, `
        @{ ParameterKey="NodeAutoScalingGroupMaxSize"; ParameterValue=$NodeASGroupMax }, `
        @{ ParameterKey="NodeInstanceType"; ParameterValue=$WorkerInstanceType }, `
        @{ ParameterKey="NodeImageId"; ParameterValue=$amiList[0].ImageId }, `
        @{ ParameterKey="KeyName"; ParameterValue=$keyName }, `
        @{ ParameterKey="BootstrapArguments"; ParameterValue=$bootstrapArgs }, `
        @{ ParameterKey="VpcId"; ParameterValue=$VpcId }, `
        @{ ParameterKey="Subnets"; ParameterValue=$SubnetIds } )
foreach ($output in $WorkerNodesStackOutputs)
{
    switch ($output.OutputKey)
    {
        NodePwxInstanceRole {
            $NodePwxInstanceRole = $output.OutputValue
        }
    }
}
#endregion

#region Enable worker nodes to join the cluster
Write-Host "Enabling worker nodes to join the EKS cluster..." -ForegroundColor Cyan
$configurationMapUrl = "https://amazon-eks.s3-us-west-2.amazonaws.com/cloudformation/2018-08-21/aws-auth-cm.yaml"
$configurationMapPath = GetFilePathInPSScriptRoot("aws-auth-cm.yaml")
if (![System.IO.File]::Exists($configurationMapPath))
{
    Invoke-WebRequest -Uri $configurationMapUrl -OutFile $configurationMapPath
}
$configMap = [System.IO.File]::ReadAllText($configurationMapPath)
$configMap = $configMap.Replace("<ARN of instance role (not instance profile)>", $NodePwxInstanceRole)
Set-Content -Path $configurationMapPath -Value $configMap
KubectlApply("aws-auth-cm.yaml")
WaitUntillReady -message "Waiting for worker nodes to join the cluster..." -kubeGetCmd "nodes" -expectedStatus "Ready"

if ($gpuOptimization -eq $true)
{
    KubectlApply("https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v1.10/nvidia-device-plugin.yml")
}
#endregion

#region adding portworx
Write-Host "Checking if Etcd installation exists..." -ForegroundColor Cyan
$existingPxEtcdEps = KubectlDescribe("ep -n kube-system -l app=etcd")
$pxEtcdExists = $false
ForEach ($str in $existingPxEtcdEps)
{
    if ($str.EndsWith("portworx-etcd-cluster"))
    {
        Write-Host "Found existing Portworx Etcd..." -ForegroundColor Yellow
        $pxEtcdExists = $true
        break;
    }
}
Write-Host "Checking if Portworx installation exists..." -ForegroundColor Cyan
$existingPxEps = KubectlDescribe("ep -n kube-system -l name=portworx")
$pxExists = $false
ForEach ($str in $existingPxEps)
{
    if ($str.EndsWith("portworx-service"))
    {
        Write-Host "Found existing Portworx Cluster..." -ForegroundColor Yellow
        $pxExists = $true
        break;
    }
}

if (!$pxEtcdExists)
{
    Write-Host "Creating ETCD Cluster for Portworx..." -ForegroundColor Cyan
    # TODO? Make parameters editable.
    # - etcd version
    # - number of etcd nodes.
    KubectlApply("etcd/rbac/cluster-role.yaml")
    KubectlApply("etcd/rbac/cluster-role-binding.yaml")
    KubectlApply("etcd/operator/etcd-operator.yaml")
    WaitUntillReady -message "Waiting for etcd-operator to be ready..." -kubeGetCmd "pods -o wide -n kube-system -l name=etcd-operator" -expectedStatus "1/1"
    # Let operator CRDs settle
    Start-Sleep -Seconds 10
    KubectlApply("etcd/etcd-cluster.yaml")
    WaitUntillReady -message "Waiting for etcd cluster to be ready..." -kubeGetCmd "pods -o wide -n kube-system -l app=etcd" -expectedStatus "1/1"

}
Else {
    Write-Host "Portworx Etcd is already installed, moving forward..." -ForegroundColor Cyan
}

if (!$pxExists)
{
    Write-Host "Installing Portworx..." -ForegroundColor Cyan
    if (![System.String]::IsNullOrWhiteSpace($pxGP2EBSDiskSize) -And [System.String]::IsNullOrWhiteSpace($pxIO1EBSDiskSize))
    {
        Write-Host "Using GP2 Only for Portworx"
        $pxStoragesOpts = """-s"", ""type=gp2,size=$pxGP2EBSDiskSize"""
    }
    ElseIf ([System.String]::IsNullOrWhiteSpace($pxGP2EBSDiskSize) -And ![System.String]::IsNullOrWhiteSpace($pxIO1EBSDiskSize)) 
    {
        Write-Host "Using IO1 Only for Portworx"
        if ([System.String]::IsNullOrWhiteSpace($pxIO1EBSDiskIOPS)){
             Write-Host "Must set -pxIO1EBSDiskIOPS" -ForegroundColor Red
             Exit
        }
        $pxStoragesOpts = """-s"", ""type=io1,size=$pxIO1EBSDiskSize,iops=$pxIO1EBSDiskIOPS"""
    }
    ElseIf (![System.String]::IsNullOrWhiteSpace($pxGP2EBSDiskSize) -And ![System.String]::IsNullOrWhiteSpace($pxIO1EBSDiskSize))
    {
        Write-Host "Using IO1 and GP2 Disks for Portworx"
        if ([System.String]::IsNullOrWhiteSpace($pxIO1EBSDiskIOPS)){
             Write-Host "Must set -pxIO1EBSDiskIOPS" -ForegroundColor Red
             Exit
        }
        $pxStoragesOpts = """-s"", ""type=gp2,size=$pxGP2EBSDiskSize"", ""-s"", ""type=io1,size=$pxIO1EBSDiskSize,iops=$pxIO1EBSDiskIOPS"""
    }
    Else {
        Write-Host "Unsupported Portworx Disk Template Parameters" -ForegroundColor Red
        Exit
    }
    $pxSpecPath = GetFilePathInPSScriptRoot("px-spec.yaml")
    if (![System.IO.File]::Exists($pxSpecPath))
    {
        Invoke-WebRequest -Uri $pxSpecUrl -OutFile $pxSpecPath
    }
    $pxSpec = [System.IO.File]::ReadAllText($pxSpecPath)
    $pxSpec = $pxSpec.Replace("<PXDISKOPTIONS>", $pxStoragesOpts)
    $uniquePXClusterName = GetUniqueIdWithName -nameString $pxClusterName
    $pxSpec = $pxSpec.Replace("<PXCLUSTERNAME>", $uniquePXClusterName)
    $pxSpec = $pxSpec.Replace("<STORAGENODESPERAZ>", $pxStorageNodesPerAz)
    Set-Content -Path $pxSpecPath -Value $pxSpec

    KubectlApply("px-spec.yaml")

    WaitUntillReady -message "Waiting for px cluster to be ready..." -kubeGetCmd "pods -o wide -n kube-system -l name=portworx" -expectedStatus "1/1"
}
Else {
    Write-Host "Portworx is already installed, moving forward..." -ForegroundColor Cyan
}
#endregion

#region Create storage classes
Write-Host "Checking if required storage classes already exist..." -ForegroundColor Cyan
$existingStorageClasses = KubectlDescribe("storageclasses")
$pxMssqlSCNormalExists = $false
$pxMssqlSCHighExists = $false
ForEach ($str in $existingStorageClasses)
{
    if ($str.EndsWith("portworx-sc"))
    {
        $pxMssqlSCNormalExists = $true
        break;
    }
    if ($str.EndsWith("high-portworx-sc"))
    {
        $pxMssqlSCHighExists = $true
        break;
    }
}
if (!$pxMssqlSCNormalExists)
{
    # TODO probably worth adding to s3 URL instead of building here.
    Write-Host "Creating k8s storage classes..." -ForegroundColor Cyan
    $pxMssqlStorageClass = "kind: StorageClass
apiVersion: storage.k8s.io/v1beta1
metadata:
  name: portworx-sc
provisioner: kubernetes.io/portworx-volume
parameters:
  repl: '3'
  snap_interval: '$pxPvcSnapshotInterval'
  io_priority:  'low'"

    $pxMssqlStorageClassYamlPath = GetFilePathInPSScriptRoot("px-mssql-storage-class.yaml")
    Set-Content -Path $pxMssqlStorageClassYamlPath -Value $pxMssqlStorageClass
    KubectlApply("px-mssql-storage-class.yaml") 

    KubectlGet("storageclass")
    Write-Host "Setting portworx-sc storage class as default..." -ForegroundColor Cyan
    # kubectl patch storageclass <your-class-name> -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
    KubectlPatch("storageclass portworx-sc -p `'{\`"metadata\`": {\`"annotations\`":{\`"storageclass.kubernetes.io/is-default-class\`":\`"true\`"}}}`'")
}
if (!$pxMssqlSCHighExists)
{
    # TODO probably worth adding to s3 URL instead of building here.
    Write-Host "Creating k8s storage classes..." -ForegroundColor Cyan
    $pxMssqlStorageClassHighIO = "kind: StorageClass
apiVersion: storage.k8s.io/v1beta1
metadata:
  name: high-portworx-sc
provisioner: kubernetes.io/portworx-volume
parameters:
  repl: '3'
  snap_interval: '$pxPvcSnapshotInterval'
  io_priority:  'high'"

    $pxMssqlStorageClassHighIOYamlPath = GetFilePathInPSScriptRoot("px-mssql-storage-high-io-class.yaml")
    Set-Content -Path $pxMssqlStorageClassHighIOYamlPath -Value $pxMssqlStorageClassHighIO
    KubectlApply("px-mssql-storage-high-io-class.yaml") 
}
#endregion

#region Creating Persistent Volume Claim
if ([System.String]::IsNullOrWhiteSpace($PVCName))
{
    $PVCName = $appName + $PVCNameSuffix
}
$PersistentVolumeClaim = "kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: " + $PVCName + "
  annotations:
    volume.beta.kubernetes.io/storage-class: " + $pxStorageClassName + "
  labels:
    mssql-group: " + $PVCName + "
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: " + $persistentVolumeClaimSize

$PVCYamlPath = GetFilePathInPSScriptRoot($PVCName+".yaml")
Set-Content -Path $PVCYamlPath -Value $PersistentVolumeClaim
KubectlApply($PVCName+".yaml")
KubectlGet("pvc $PVCName")
#endregion

#region Create SA password
Write-Host "Checking if SA password secret already exists..." -ForegroundColor Cyan
$saPassSecret = KubectlDescribe("secret $SA_PasswordSecretName")
if ([System.String]::IsNullOrWhiteSpace($saPassSecret) -or $saPassSecret[0].Contains("(NotFound)"))
{
    $creds = Get-Credential -UserName "sa" -Message "Please enter sa password. The password must be at least 8 characters long and contain characters from three of the following four sets: Uppercase letters, Lowercase letters, Base 10 digits, and Symbols.."
    Write-Host "Creating secret for sa password..." -ForegroundColor Cyan
    $createPasswordCommand = "secret generic {0} --from-literal=SA_PASSWORD={1}" -f $SA_PasswordSecretName, $creds.GetNetworkCredential().password
    KubectlCreate($createPasswordCommand)
}
#endregion

#region Create the SQL Server container deployment
Write-Host "Checking if SQL Server container deployment already exists..." -ForegroundColor Cyan
$checkDeploymanetExist = KubectlDescribe("deployment $deploymentName")
if ([System.String]::IsNullOrWhiteSpace($checkDeploymanetExist) -or $checkDeploymanetExist[0].Contains("(NotFound)"))
{
Write-Host "Creating SQL Server container deployment on EKS cluster..." -ForegroundColor Cyan
$internalSvcStr = "";
if ($internalService -eq $true)
{
  $internalSvcStr = "service.beta.kubernetes.io/aws-load-balancer-internal: 0.0.0.0/0"
}
$NlbAnnotation = "";
if ($useNlb -eq $true)
{
    $NlbAnnotation = "service.beta.kubernetes.io/aws-load-balancer-type: `"nlb`""
}
Write-Host "This SQL Server container is being configured to always have minimum $minCpu vCPU available." -ForegroundColor Yellow
if ($minCpu -ne $maxCpu)
{
    Write-Host "At times when more vCPU is available on its worker node, it can also burst to $maxCpu vCPU if it needs it." -ForegroundColor Yellow
}
$sqlDeploymentYaml = "apiVersion: apps/v1beta1
kind: Deployment
metadata:
  name: " + $deploymentName + "
spec:
  replicas: 1
  template:
    metadata:
      labels:
        app: " + $appName + "
    spec:
      terminationGracePeriodSeconds: 10
      containers:
      - name: mssql
        image: microsoft/mssql-server-linux
        resources:
          limits:
            cpu: `"" + $maxCpu + "`"
          requests:
            cpu: `"" + $minCpu + "`"
        ports:
        - containerPort: 1433
        env:
        - name: ACCEPT_EULA
          value: `"Y`"
        - name: MSSQL_PID
          value: `"" + $MSSQL_PID + "`"
        - name: SA_PASSWORD
          valueFrom:
            secretKeyRef:
              name: " + $SA_PasswordSecretName + "
              key: SA_PASSWORD 
        volumeMounts:
        - name: mssqldb
          mountPath: /var/opt/mssql
      volumes:
      - name: mssqldb
        persistentVolumeClaim:
          claimName: " + $PVCName + "
---
apiVersion: v1
kind: Service
metadata:
  name: " + $deploymentName + "
  annotations:
    " + $NlbAnnotation + "
    " + $internalSvcStr + "
spec:
  selector:
    app: " + $appName + "
  ports:
    - protocol: TCP
      port: " + $appExternalPort + "
      targetPort: 1433
  type: LoadBalancer"

$sqlDeplYamlPath = GetFilePathInPSScriptRoot($appName+"-sqldeployment.yaml")
Set-Content -Path $sqlDeplYamlPath -Value $sqlDeploymentYaml
KubectlApply($appName+"-sqldeployment.yaml")
KubectlGet("services")
#endregion

#Verify failure and recovery
KubectlGet("pods --all-namespaces")

#region retrieving SQL Server endpoint (NLB)...
WaitUntillReady -message "Waiting for SQL Server to be ready..." -kubeGetCmd "pods -l app=$appName" -expectedStatus "1/1"

# Wait a little after container is started for EKS to creat NLB
Start-Sleep -Seconds 30

$json = KubectlGet("services $deploymentName -o json")
$svcObj = ConvertFromCliJson($json)
$mssqlEndpoint = $svcObj.status.loadBalancer.ingress[0].hostname
Write-Host "SQL Server deployed on K8s cluster using AWS EKS." -ForegroundColor Green
Write-Host "This is the SQL Server endpoint (use in connection string):" -ForegroundColor Cyan
Write-Host $mssqlEndpoint -ForegroundColor Yellow
}
Else{
    Write-Host "Deployment $deploymentName exists.."  -ForegroundColor Red
}
#endregion
