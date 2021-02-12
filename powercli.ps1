$lib_version="0.7powercli"
$VMware_vendor="VMware"
$VMware_ESXi="$($VMware_vendor) ESXi"

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

Write-Host VMHosts -------------------

#Хосты
foreach ($VMhost in $VMhosts) {
	#собираем мать из модели сервера
	$strMb= "{`"motherboard`":{`"manufacturer`":`"$($VMhost.Manufacturer)`",`"product`":`"$($VMhost.Model)`",`"serial`":`"`"}}"
	$strCpu="{`"processor`":`"$($VMhost.ProcessorType) (x$($VMhost.NumCpu) cores)`"}"
	$strMem="{`"memorybank`": {`"manufacturer`":`"$($VMhost.Manufacturer)`",`"capacity`":`"$([math]::Round($VMHost.MemoryTotalMb/1024,0)*1024)`",`"serial`":`"`"}}"
	$strOS="$($VMware_ESXi), v$($VMHost.Version)"
	if ($VMhost.name -match "^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$") {
		$strComp=$VMhost.NetworkInfo.Hostname
		$strDomain=$VMhost.NetworkInfo.DomainName.split('.')[0]
	} else { 
		$strComp=$VMhost.name.split('.')[0]
		$strDomain=$VMhost.name.split('.')[1]
	}
	$intDomain=getInventoryId 'domains' $strDomain
	$strNow=Get-Date -Format "yyyy-MM-dd HH:mm:ss"
	$strIfaces=""
	foreach ($VMiface in $VMifaces) {
		if (($VMiface.VMHost.name -eq $VMHost.name) -and ($VMiface.IP.Length -gt 0)) {
			$strIfaces="$($strIfaces)$($VMiface.IP)`n"
		}
	}
	#$vmhost
	$data=
		"domain_id=$($intDomain)&", 
		"name=$([System.Web.HttpUtility]::UrlEncode($strComp)) &", 
		"os=$([System.Web.HttpUtility]::UrlEncode($strOS))&",
		"raw_hw=$([System.Web.HttpUtility]::UrlEncode("$($strMb),$($strCpu),$($strMem)"))&" ,
		"raw_soft=&",
		"raw_version=$([System.Web.HttpUtility]::UrlEncode($lib_version))&",
		"ip=$([System.Web.HttpUtility]::UrlEncode($strIfaces))&",
		"updated_at=$([System.Web.HttpUtility]::UrlEncode($strNow))"

	#$data
	if ([int]$intDomain -gt 0) {
		$intComp=getInventoryId 'comps' "$($strDomain)/$($strComp)"
		setInventoryData 'comps' $intComp $data | out-null
	}
}
Write-Host VMs -------------------

#Виртуалки
$VMs = get-VM | select name,PowerState,NumCpu,MemoryGb,ProvisionedSpaceGB,Guest,VMHost
foreach( $VM in $VMs) {
	if ($VM.PowerState -eq 'PoweredOn' ) {
		#запрос дополнительной информации недоступной через Get-VM (нам нужно число ядер на сокет)
		
		#три раза переделывал нижнюю строку. Я особо не вчитыался в доку по Get-View
		#и к сожалению только методом проб и ошибок и кучи потерянного времени пришел к выводу что фильтр
		#типа name="чтото" работает не сравнением строк а через Regex, а это значит что нужно
		# 1. Экранировать служебные для регекспа символы
		# 2. Явно обозначать что мы ищем ^name$ (^-начало строки, а $ - конец) иначе находятся name2, name_clone и т.п.
		$VMView=Get-view  -ViewType VirtualMachine -filter @{"name"="^$([RegEx]::Escape($VM.Name))$"}
		$VMGuest=get-vmguest $VM.name | select vmName,Hostname,OSFullName,GuestFamily,Disks,IPAddress
		$VMGuest
		$VMView.config.hardware
		#$strMb= "{`"motherboard`":{`"manufacturer`":`"$($VMhost.Manufacturer)`",`"product`":`"$($VMhost.Model)`",`"serial`":`"`"}}"
		$strCpu="{`"processor`": {`"model`":`"$($VMware_vendor)`",`"cores`":`"$($VM.NumCpu*$VMView.config.hardware.NumCoresPerSocket)`"}}"
		$strMem="{`"memorybank`": {`"manufacturer`":`"$($VMware_vendor)`",`"capacity`":`"$($VM.MemoryGB*1024)`",`"serial`":`"`"}}"
		$strDisks=""
		foreach ($VMDisk in $VM.Guest.disks) {
			#{"harddisk":{"model":"VMware Virtual disk SCSI Disk Device","size":"107"}}
			$strdisks="$($strDisks),{`"harddisk`":{`"model`":`"VMware Virtual disk SCSI Disk Device`",`"size`":`"$([math]::Round($VMDisk.CapacityGB))`"}}"
		}
		$strOS=$VMGuest.OSFullName
		
		#если у нас есть хостнейм (#бывает и нулл)
		if ($VMGuest.Hostname) {	
			#Write-Host $VMGuest.Hostname ----------------------
			#разгребаем FQDN
			if ($VMGuest.HostName.split('.').count -gt 1 ) {
				$strComp=$VMGuest.HostName.split('.')[0]
				$strDomain=$VMGuest.HostName.split('.')[1]
				$intDomain=getInventoryId 'domains' $strDomain
			} else {
				$strComp=$VMGuest.HostName
				#если домена нет. будем искать по связке имя+IP
				Write-Host -foregroundColor Yellow "HOST DOMAIN NOT FOUND, Searching by name and ip: " , name	, ($VMGuest.IPAddress -join " ")
				Write-Host -foregroundColor Yellow "name=$($strComp)&ip=$($VMGuest.IPAddress -join " ")"
				$objComp=getInventoryObj 'comps' "search?name=$($strComp)&ip=$($VMGuest.IPAddress -join " ")"

				#если нашли, то вытаскиваем имя домена
				if ($objComp) {
					$intDomain=$objComp.domain_id
					$objDomain=getInventoryObj 'domains' $intDomain
					$strdomain=$objDomain.name
					Write-Host -foregroundColor Green "Found Domain:",$intDomain
				} else {
					Write-Host -foregroundColor Red "Domain not found, using default: ", $inventory_defaultDomain
					$strDomain=$inventory_defaultDomain
					$intDomain=getInventoryId 'domains' $inventory_defaultDomain
				}
			}


			#Ищем, а есть ли уже в базе наш ESXi хост и есть ли у него АРМ?
			if ($VM.VMhost.name -match "^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$") {
				$strHost="$($VM.VMhost.NetworkInfo.Hostname).$($VM.VMhost.NetworkInfo.DomainName)"
			} else { 
				$strHost=$VM.VMHost.name
			}
	
			$objESXi=getInventoryFqdnComp $strHost
			if ($objESXi -and $objESXi.arm_id) {
				#Все есть! Круть!
				$intArm=$objESXi.arm_id
			} else {
				#нету ножек - нет варенья
				$intArm=$false
				Write-Host HOST ARM NOT FOUND $strHost
			}

			$strNow=Get-Date -Format "yyyy-MM-dd HH:mm:ss"
			$strIfaces=$VMGuest.IPAddress -join "`n"



			if ([int]$intDomain -gt 0) {
				#тут короче такая логика, мы узнаем, есть ли эта машина в базе
				#если она есть, то мы смотрим, есть ли по ней данные от скрипта из ОС (более полный набор)
				#если есть, то мы просто помещаем ее в тот, АРМ, на хосте которого она крутится
				#если нет, то мы полностью отправляем информацию о ней
				$objComp=getInventoryObj 'comps' "$($strDomain)/$($strComp)"

				$data=
					"domain_id=$($intDomain)&", 
					"name=$([System.Web.HttpUtility]::UrlEncode($strComp)) &", 
					"os=$([System.Web.HttpUtility]::UrlEncode($strOS))&",
					"raw_hw=$([System.Web.HttpUtility]::UrlEncode("$($strCpu),$($strMem)$($strDisks)"))&",
					"ignore_hw=1&",
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
					$data="arm_id=$($intArm)&ignore_hw=1"
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
