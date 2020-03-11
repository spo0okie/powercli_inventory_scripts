$lib_version="0.2.1powercli"
$VMware_vendor="VMware"
$VMware_ESXi="$($VMware_vendor) ESXi"

. "$($PSScriptRoot)\config.priv.ps1"
. "$($PSScriptRoot)\lib_inventory.ps1"

#Install-Module -Name VMware.PowerCLI –AllowClobber
#Set-ExecutionPolicy unrestricted
Import-Module VMware.VimAutomation.Core

#Пытаемся игнорировать проблемы с сертификатами на хостах
Set-PowerCliConfiguration -InvalidCertificateAction Ignore -confirm:$false 

#строка выше не решает проблемы с сертификатом. 
#поэтому вставляем хак отсюда (помогло кстати)
#https://communities.vmware.com/thread/613947
add-type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(
        ServicePoint srvPoint, X509Certificate certificate,
        WebRequest request, int certificateProblem) {
        return true;
    }
}
"@
$AllProtocols = [System.Net.SecurityProtocolType]'Ssl3,Tls,Tls11,Tls12'
[System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

 
Connect-VIServer -server chl-vcenter.azimuth.holding.local -protocol https -User $inventory_VMWareUser -Password $inventory_VMWarePassword -force #-Verbose

#собираем интерфейсы:
$VMifaces = Get-VMHostNetworkAdapter | select VMhost, IP

#собираем хосты
$VMhosts = Get-VMHost | select name,ProcessorType,NumCpu,Manufacturer,Model,MemoryTotalMB,Version,NetworkInfo


foreach ($VMhost in $VMhosts) {
	#собираем мать из модели сервера
	$strMb= "{`"motherboard`":{`"manufacturer`":`"$($VMhost.Manufacturer)`",`"product`":`"$($VMhost.Model)`",`"serial`":`"`"}}"
	$strCpu="{`"processor`":`"$($VMhost.ProcessorType) (x$($VMhost.NumCpu) cores)`"}"
	$strMem="{`"memorybank`": {`"manufacturer`":`"$($VMhost.Manufacturer)`",`"capacity`":`"$([math]::Round($VMHost.MemoryTotalMb/1024,0)*1024)`",`"serial`":`"`"}}"
	$strOS="$($VMware_ESXi), v$($VMHost.Version)"
	$strComp=$VMhost.name.split('.')[0]
	$strDomain=$VMhost.name.split('.')[1]
	$intDomain=getInventoryId 'domains' $strDomain
	$strNow=Get-Date -Format "yyyy-MM-dd HH:mm:ss"
	$strIfaces=""
	foreach ($VMiface in $VMifaces) {
		if (($VMiface.VMHost.name -eq $VMHost.name) -and ($VMiface.IP.Length -gt 0)) {
			$strIfaces="$($strIfaces)$($VMiface.IP)`n"
		}
	}
	$vmhost
	$data=
		"domain_id=$($intDomain)&", 
		"name=$([System.Web.HttpUtility]::UrlEncode($strComp)) &", 
		"os=$([System.Web.HttpUtility]::UrlEncode($strOS))&",
		"raw_hw=$([System.Web.HttpUtility]::UrlEncode("$($strMb),$($strCpu),$($strMem)"))&" ,
		"raw_soft=&",
		"raw_version=$([System.Web.HttpUtility]::UrlEncode($lib_version))&",
		"ip=$([System.Web.HttpUtility]::UrlEncode($strIfaces))&",
		"updated_at=$([System.Web.HttpUtility]::UrlEncode($strNow))"

	$data
	if ([int]$intDomain -gt 0) {
		$intComp=getInventoryId 'comps' "$($strDomain)/$($strComp)"
		setInventoryData 'comps' $intComp $data
	}
}



get-VM | select name,PowerState,NumCpu,MemoryGb,ProvisionedSpaceGB,Guest

#get-vm | get-vmguest | select vmName,Hostname,OSFullName,GuestFamily,Disks,IPAddress
 