FROM microsoft/powershell
SHELL ["pwsh", "-command"]

RUN apt update; \
	apt install -y vim; \
	apt install -y python-pip; \
	pip install --upgrade pip; \
	pip install awscli --upgrade --user; \
	cp /root/.local/bin/aws /usr/bin/; \
	Install-Module -Scope CurrentUser -Name AWSPowerShell.NetCore -Force; \
	Get-Module -ListAvailable -Name aws*;

ENV eksdir /eks-px-mssql
RUN mkdir /eks-px-mssql
COPY Deploy-MSSQLServerOnEKSWithPortworx.ps1 $eksdir
ADD etcd $eksdir/etcd
ADD specs $eksdir/specs
WORKDIR $eksdir

