﻿$lib_version="0.8powercli"
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




#запись данных о пользователе в БД
function pushVMHostData() {
	param
	(
		[object]$VMHost,
        $VMIfaces
	)

    #если имя ноды - IP адрес, то выдергиваем hostname
    if ($VMhost.name -match "^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$") {
		$strComp=$VMhost.NetworkInfo.Hostname
		$strDomain=$VMhost.NetworkInfo.DomainName.split('.')[0]
        $strFullName="$($strComp).$($VMhost.NetworkInfo.DomainName)"
	} else {
		$strComp=$VMhost.name.split('.')[0]
		$strDomain=$VMhost.name.split('.')[1]
        $strFullName=$VMhost.name
	}
    
    #Ищем домен
	$intDomain=getInventoryId 'domains' $strDomain
    if ([int]$intDomain -lt 0) {
        #не нашли
        errorLog "ESXi host domain not found: $($strFullName)"
        return false
    }

    #Ищем OS
	$intComp=getInventoryId 'comps' "$($strDomain)/$($strComp)" | out-null
    if ([int]$intComp -lt 0) {
        #не нашли
        errorLog "ESXi OS not found: $($strFullName)"
        return false
    }

	$strNow=getUTCNow
	$strMb= "{`"motherboard`":{`"manufacturer`":`"$($VMhost.Manufacturer)`",`"product`":`"$($VMhost.Model)`",`"serial`":`"`"}}"
	$strCpu="{`"processor`":`{`"model`":`"$($VMhost.ProcessorType)`",`"cores`":`"$($VMhost.NumCpu)`"}}"
	$strMem="{`"memorybank`": {`"manufacturer`":`"$($VMhost.Manufacturer)`",`"capacity`":`"$([math]::Round($VMHost.MemoryTotalMb/1024,0)*1024)`",`"serial`":`"`"}}"
	$strOS="$($VMware_ESXi), v$($VMHost.Version)"
	
	
    $strIfaces=""
    $strMACs=""
	foreach ($VMiface in $VMifaces) {
		if (($VMiface.VMHost.name -eq $VMHost.name) -and ($VMiface.IP.Length -gt 0)) {
			$strIfaces="$($strIfaces)$($VMiface.IP)`n"
			$strMACs="$($strMACs)$($VMiface.MAC)`n"
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
		"mac=$([System.Web.HttpUtility]::UrlEncode($strMACs))&",
		"updated_at=$([System.Web.HttpUtility]::UrlEncode($strNow))"

	#$data
	setInventoryData 'comps' $intComp $data | out-null
    Log "ESXi host $($strFullName) - OK"
	return true
}



function pushVMData() {
	param
	(
		[object]$VM
    )
	#запрос дополнительной информации недоступной через Get-VM (нам нужно число ядер на сокет)
	#три раза переделывал нижнюю строку. Я особо не вчитыался в доку по Get-View
	#и к сожалению только методом проб и ошибок и кучи потерянного времени пришел к выводу что фильтр
	#типа name="чтото" работает не сравнением строк а через Regex, а это значит что нужно
	# 1. Экранировать служебные для регекспа символы
	# 2. Явно обозначать что мы ищем ^name$ (^-начало строки, а $ - конец) иначе находятся name2, name_clone и т.п.
	$VMView=Get-view  -ViewType VirtualMachine -filter @{"name"="^$([RegEx]::Escape($VM.Name))$"}
	$VMGuest=get-vmguest $VM.name | select vmName,Hostname,OSFullName,GuestFamily,Disks,IPAddress
	#$VMGuest
	$VMView.config.hardware
	#$strMb= "{`"motherboard`":{`"manufacturer`":`"$($VMhost.Manufacturer)`",`"product`":`"$($VMhost.Model)`",`"serial`":`"`"}}"
	$strCpu="{`"processor`": {`"model`":`"$($VMware_vendor)`",`"cores`":`"$($VM.NumCpu*$VMView.config.hardware.NumCoresPerSocket)`"}}"
	$strMem="{`"memorybank`": {`"manufacturer`":`"$($VMware_vendor)`",`"capacity`":`"$($VM.MemoryGB*1024)`",`"serial`":`"`"}}"
	$strDisks=""
	foreach ($VMDisk in $VM.Guest.disks) {
		$strdisks="$($strDisks),{`"harddisk`":{`"model`":`"VMware Virtual disk SCSI Disk Device`",`"size`":`"$([math]::Round($VMDisk.CapacityGB))`"}}"
	}
	$strOS=$VMGuest.OSFullName
	#если у нас есть хостнейм (#бывает и нулл)
	if (!$VMGuest.Hostname) {
		errorLog "VM: $($VM.name) no hostname"
    }

	if ($VMGuest.HostName.split('.').count -gt 1 ) {
		$strComp=$VMGuest.HostName.split('.')[0]
		$strDomain=$VMGuest.HostName.split('.')[1]
		$intDomain=getInventoryId 'domains' $strDomain
        if ([int]$intDomain -lt 0) {
            errorLog "VM: $($strDomain)\$($strComp) domain not found in Inventory"
            return false
        }
	} else {
		$strComp=$VMGuest.HostName
        Log "WARNING: VM: $($strComp) ($($VMGuest.IPAddress -join " ")) no DOMAIN in ESXi"
		#если домена нет. будем искать по связке имя+IP
		#Write-Host -foregroundColor Yellow "HOST DOMAIN NOT FOUND, Searching by name and ip: " , name, ($VMGuest.IPAddress -join " ")
		#Write-Host -foregroundColor Yellow "name=$($strComp)&ip=$($VMGuest.IPAddress -join " ")"
            
		$objComp=getInventoryObj 'comps' "search?name=$($strComp)&ip=$($VMGuest.IPAddress -join " ")"

		#если нашли, то вытаскиваем имя домена
		if ($objComp) {
			$intDomain=$objComp.domain_id
			$objDomain=getInventoryObj 'domains' $intDomain
			$strdomain=$objDomain.name
            Log "WARNING: VM: $($strDomain)\$($strComp) no DOMAIN in ESXi //found in inventory by IP($($VMGuest.IPAddress -join " "))"
			#Write-Host -foregroundColor Green "Found Domain:",$intDomain
		} else {
			#Write-Host -foregroundColor Red "Domain not found, using default: ", $inventory_defaultDomain
            errorLog "VM: no domain for $($strComp) in ESXi"
            return false
			#$strDomain=$inventory_defaultDomain
			#$intDomain=getInventoryId 'domains' $inventory_defaultDomain
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
		errorLog "VM: no ESXi host $strHost found in Inventory"
	}

    	
	$strNow=(Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss")
	$strIfaces=$VMGuest.IPAddress -join "`n"
	$strIfacesMacs=$VMGuest.MACAddress -join "`n"

	#тут короче такая логика, мы узнаем, есть ли эта машина в базе
	#если она есть, то мы смотрим, есть ли по ней данные от скрипта из ОС (более полный набор)
	#если есть, то мы просто помещаем ее в тот, АРМ, на хосте которого она крутится
	#если нет, то мы полностью отправляем информацию о ней
	$objComp=getInventoryObj 'comps' "$($strDomain)/$($strComp)"

	$data=
		"domain_id=$($intDomain)&", 
		"name=$([System.Web.HttpUtility]::UrlEncode($strComp))&", 
		"os=$([System.Web.HttpUtility]::UrlEncode($strOS))&",
		"raw_hw=$([System.Web.HttpUtility]::UrlEncode("$($strCpu),$($strMem)$($strDisks)"))&",
		"ignore_hw=1&",
		"raw_soft=&",
		"raw_version=$([System.Web.HttpUtility]::UrlEncode($lib_version))&",
		"ip=$([System.Web.HttpUtility]::UrlEncode($strIfaces))&",
		"mac=$([System.Web.HttpUtility]::UrlEncode($strIfacesMacs))&",
		"updated_at=$([System.Web.HttpUtility]::UrlEncode($strNow))"

    #если нашли текущий АРМ - закрепляем
	if ($intArm) {
		$data="$($data)&arm_id=$($intArm)"
	} 

	#ОС есть в БД, она обновлена не этим скриптом и мы знаем в какой АРМ ее положить
	if ($objComp -and $intArm -and ( -not $objComp.raw_version.contains("powercli"))) {
		$data="arm_id=$($intArm)&ignore_hw=1"
		setInventoryData 'comps' $objComp.id $data | out-null
		spooLog "VM: $($strDomain)\$($strComp) - OK (arm update only)"
	} elseif ($objComp) {
		#Write-Host Updating $VMGuest.HostName
		setInventoryData 'comps' $objComp.id $data | out-null
		spooLog "VM: $($strDomain)\$($strComp) - OK (update)"
	} else {
		#Write-Host Missing $VMGuest.HostName
		setInventoryData 'comps' -1 $data | out-null
		spooLog "VM: $($strDomain)\$($strComp) - OK (new OS)"
	}
	return true
}
