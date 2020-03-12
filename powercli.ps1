$lib_version="0.4powercli"
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

 
Connect-VIServer -server $VMWare_vcenter -protocol https -User $inventory_VMWareUser -Password $inventory_VMWarePassword -force #-Verbose
#собираем интерфейсы:
$VMifaces = Get-VMHostNetworkAdapter | select VMhost, IP

#собираем хосты
$VMhosts = Get-VMHost | select name,ProcessorType,NumCpu,Manufacturer,Model,MemoryTotalMB,Version,NetworkInfo

<#

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

$VMs = get-VM | select name,PowerState,NumCpu,MemoryGb,ProvisionedSpaceGB,Guest | Tee-object -Variable VM | Foreach-object{
	if ($_.PowerState -eq 'PoweredOn' ) {
		$_
		get-vmguest -VM $_ | select vmName,Hostname,OSFullName,GuestFamily,Disks,IPAddress
	}
}

#>

#$VMs = get-VM | select name,PowerState,NumCpu,MemoryGb,ProvisionedSpaceGB,Guest
#foreach ($VM in $VMs)  {
#get-VM | select name,PowerState,NumCpu,MemoryGb,ProvisionedSpaceGB,Guest | Tee-object -Variable VM | get-vmguest select vmName,Hostname,OSFullName,GuestFamily,Disks,IPAddress | Foreach-object{
#	$VM
#	$_
#}

#https://communities.vmware.com/thread/571475

$VMs = get-VM | select name,PowerState,NumCpu,MemoryGb,ProvisionedSpaceGB,Guest,VMHost
foreach( $VM in $VMs) {
	if ($VM.PowerState -eq 'PoweredOn' ) {
		#$VM
		$VMGuest=get-vmguest $VM.name | select vmName,Hostname,OSFullName,GuestFamily,Disks,IPAddress
		#$VMGuest
		#$strMb= "{`"motherboard`":{`"manufacturer`":`"$($VMhost.Manufacturer)`",`"product`":`"$($VMhost.Model)`",`"serial`":`"`"}}"
		$strCpu="{`"processor`":`"$($VMware_vendor) (x$($VM.NumCpu) cores)`"}"
		$strMem="{`"memorybank`": {`"manufacturer`":`"$($VMware_vendor)`",`"capacity`":`"$($VM.MemoryGB*1024)`",`"serial`":`"`"}}"
		$strOS=$VMGuest.OSFullName
		
		#если у нас есть хостнейм (#бывает и нулл)
		if ($VMGuest.Hostname) {	
			#Write-Host $VMGuest.Hostname ----------------------
			#разгребаем FQDN
			if ($VMGuest.HostName.split('.').count -gt 1 ) {
				$strComp=$VMGuest.HostName.split('.')[0]
				$strDomain=$VMGuest.HostName.split('.')[1]
			} else {
				$strComp=$VMGuest.HostName
				$strDomain=$inventory_defaultDomain
			}

			#Ищем, а есть ли уже в базе наш ESXi хост и есть ли у него АРМ?
			$objESXi=getInventoryFqdnComp $VM.VMHost.name
			if ($objESXi -and $objESXi.arm_id) {
				#Все есть! Круть!
				$intArm=$objESXi.arm_id
			} else {
				#нету ножек - нет варенья
				$intArm=$false
				Write-Host not found $VM.VMHost.name
			}

			$strNow=Get-Date -Format "yyyy-MM-dd HH:mm:ss"
			$strIfaces=$VMGuest.IPAddress -join "`n"

			$intDomain=getInventoryId 'domains' $strDomain
			if ([int]$intDomain -gt 0) {
				#тут короче такая логика, мы узнаем, есть ли эта машина в базе
				#если она есть, то мы смотрим, есть ли по ней данные от скрипта из ОС (более полный набор)
				#если есть, то мы просто помещаем ее в тот, АРМ, на хосте которого она крутится
				#если нет, то мы полностью отправляем информацию о ней
				$objComp=getInventoryObj 'comps' "$($strDomain)/$($strComp)"
				#$objComp

				$data=
					"domain_id=$($intDomain)&", 
					"name=$([System.Web.HttpUtility]::UrlEncode($strComp)) &", 
					"os=$([System.Web.HttpUtility]::UrlEncode($strOS))&",
					"raw_hw=$([System.Web.HttpUtility]::UrlEncode("$($strCpu),$($strMem)"))&" ,
					"raw_soft=&",
					"raw_version=$([System.Web.HttpUtility]::UrlEncode($lib_version))&",
					"ip=$([System.Web.HttpUtility]::UrlEncode($strIfaces))&",
					"updated_at=$([System.Web.HttpUtility]::UrlEncode($strNow))"
				if ($intArm) {
					$data="$($data)&arm_id=$($intArm)"
				}

				#ОС есть в БД, она создана не этим скриптом и мы знаем в какой АРМ ее положить
				if ($objComp -and $intArm -and ( -not $objComp.raw_version.contains("powercli"))) {
					Write-Host Found $strComp by $objComp.raw_version '(moving)'
					$data="arm_id=$($intArm)"
					setInventoryData 'comps' $objComp.id $data | out-null
				} elseif ($objComp) {
					Write-Host Updating $VMGuest.HostName
					setInventoryData 'comps' $objComp.id $data | out-null
				} else {
					Write-Host Missing $VMGuest.HostName
					setInventoryData 'comps' -1 $data
				}
				
			} else {
				Write-Host Missing DOMAIN $strDomain for $VMGuest.HostName
			}
		} else {
			Write-Host NO GUEST! $VM.name
		}

		#$data
	}
}

#get-vm | get-vmguest | select vmName,Hostname,OSFullName,GuestFamily,Disks,IPAddress
 