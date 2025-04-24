$lib_version="1.0powercli"
$VMware_vendor="VMware"
$script:VMware_ESXi="$($VMware_vendor) ESXi"

#Install-Module -Name VMware.PowerCLI –AllowClobber
#Set-ExecutionPolicy unrestricted
Import-Module VMware.VimAutomation.Core | Out-Null

#отключаем уведомление об участии в программе обратной связи
Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP $false -confirm:$false | Out-Null
#Пытаемся игнорировать проблемы с сертификатами на хостах
Set-PowerCliConfiguration -InvalidCertificateAction Ignore -confirm:$false | Out-Null


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




#запись данных о ESXI гипервизоре в БД
function pushVMHostData() {
	param
	(
		[object]$VMHost,
		$VMIfaces
	)

	#если имя ноды - IP адрес, то выдергиваем hostname
	if ($VMhost.name -match "^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$") {
		$strComp=$VMhost.NetworkInfo.Hostname
		$strFullName="$strComp.$($VMhost.NetworkInfo.DomainName)"
	} else {
		$strComp=$VMhost.name.split('.')[0]
		$strFullName=$VMhost.name
	}

	#Write-Host -ForegroundColor Yellow $strFullName


	#write-host -ForegroundColor Green $intComp

	$strNow=getUTCNow
	$strMb= -join('{"motherboard":{',
		'"manufacturer":"', $VMhost.Manufacturer ,'",',
		'"product":"', $VMhost.Model ,'",',
		'"serial":""',
	'}}')

	$strCpu= -join('{"processor":{',
		'"model":"', ($VMhost.ProcessorType -replace '\s+',' ' ) ,'",',
		'"cores":"', $VMhost.NumCpu ,'"',
	'}}')

	$strMem= -join('{"memorybank": {',
		'"manufacturer":"', $VMhost.Manufacturer ,'",',
		'"capacity":"', [string]([math]::Round($VMHost.MemoryTotalMb)) ,'",',
		'"serial":""',
	'}}')

	$strOS="$($VMware_ESXi), v$($VMHost.Version)"
	
	
	$strIfaces=""
	$strMACs=""
	foreach ($VMiface in $VMifaces) {
		if (($VMiface.VMHost.name -eq $VMHost.name) -and ($VMiface.IP.Length -gt 0)) {
			#$VMiface
			$strIfaces="$($strIfaces)$($VMiface.IP)`n"
			$strMACs="$($strMACs)$($VMiface.MAC)`n"
		}
	}

	$uuid=getVMhostUUID $VMHost
	#$vmhost
	$data= @{
		name=[System.Web.HttpUtility]::UrlEncode($strFullName);
		os=[System.Web.HttpUtility]::UrlEncode($strOS);
		raw_hw=[System.Web.HttpUtility]::UrlEncode("$($strMb),$($strCpu),$($strMem)");
		raw_soft="";
		raw_version=[System.Web.HttpUtility]::UrlEncode($lib_version);
		ip=[System.Web.HttpUtility]::UrlEncode($strIfaces);
		mac=[System.Web.HttpUtility]::UrlEncode($strMACs);
		external_links=$(@{'VMWare.hostUUID'=$uuid}|ConvertTo-Json);
	}
	#$data
	$result=pushInventoryData 'comps' $data

	#$result | fl
	if ($result) {
		spooLog "ESXi host $($strFullName) - OK"
	} else {
		errorLog "ESXi host $($strFullName) - Error ($method)"
		Write-Host -ForegroundColor Cyan "name=$strFullName"
		Write-Host -ForegroundColor Cyan "os=$strOS"
		Write-Host -ForegroundColor Cyan "raw_hw=`"$strMb,$strCpu,$strMem`""
		Write-Host -ForegroundColor Cyan "raw_soft="
		Write-Host -ForegroundColor Cyan "raw_version=$lib_version"
		Write-Host -ForegroundColor Cyan "ip=$strIfaces"
		Write-Host -ForegroundColor Cyan "mac=$strMACs"
	}
	return
}


function pushVMData() {
	param
	(
		[object]$VM,
		[object]$objComp=$null
	)
	#Log "Parsing $($VM.Name) $($VM.Id)"
	#запрос дополнительной информации недоступной через Get-VM (нам нужно число ядер на сокет)
	#три раза переделывал нижнюю строку. Я особо не вчитыался в доку по Get-View
	#и к сожалению только методом проб и ошибок и кучи потерянного времени пришел к выводу что фильтр
	#типа name="чтото" работает не сравнением строк а через Regex, а это значит что нужно
	# 1. Экранировать служебные для регекспа символы
	# 2. Явно обозначать что мы ищем ^name$ (^-начало строки, а $ - конец) иначе находятся name2, name_clone и т.п.
	#$VMView=$VM|Get-View # -ViewType VirtualMachine
	#$VMView=Get-View $VM
	#$VMGuest=Get-VMGuest $VM #.name | select vmName,Hostname,OSFullName,GuestFamily,Disks,IPAddress
	$VMGuest=getCachedVmGuest($VM);
	#$VMGuest
	#$VMView.config.hardware
	$uuid=getVMUUID $VM;
	#если у нас есть хостнейм (#бывает и нулл)
	if (!$VMGuest.Hostname) {
		errorLog "VM: $($hostname) ($($VM.Name) : $($uuid)) no hostname"
		return
	}

	$strFullName=$VMGuest.HostName;
	if ($strFullName.split('.').count -gt 1 ) {
		$strComp=$strFullName.split('.')[0]		
	} else {
		$strComp=$strFullName
		#warningLog "VM: $($strComp) ($($arrIPv4 -join " ")) no DOMAIN in ESXi"
		#если домена нет. будем искать по связке имя+IP
		#Write-Host -foregroundColor Yellow "HOST DOMAIN NOT FOUND, Searching by name and ip: " , name, ($VMGuest.IPAddress -join " ")
		#Write-Host -foregroundColor Yellow "name=$($strFullName)&ip=$($VMGuest.IPAddress -join " ")"
		if ( -not $objComp) {
			$objComp=getInventoryObj 'comps' "$($strFullName)&ip=$($arrIPv4 -join ' ')&expand=domain"
			#$objComp
		}

		#если нашли, то вытаскиваем имя домена
		if ($objComp) {
			$strdomain=$objComp.domain.fqdn
			$strFullName="$($strFullName).$($strDomain)";
			warningLog "VM: $strFullName no FQDN hostname in ESXi //found in inventory by IP($($arrIPv4 -join " "))"
			#Write-Host -foregroundColor Green "Found Domain:",$intDomain
		} else {
			#Write-Host -foregroundColor Red "Domain not found, using default: ", $inventory_defaultDomain
			errorLog "VM: $($strComp) ($($_.Name) : $($uuid) : $($arrIPv4 -join ' ')) нет FQDN в VMWare (без домена не могу добавить в инвентори)"
			return
		}
	}

	#spooLog "VM parsing $($strFullName)..."
	#Ищем, а есть ли уже в базе наш ESXi хост и есть ли у него АРМ?
	if ($VM.VMhost.name -match "^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$") {
		$strHost="$($VM.VMhost.NetworkInfo.Hostname).$($VM.VMhost.NetworkInfo.DomainName)"
	} else { 
		$strHost=$VM.VMHost.name
	}
	
	$objESXi=getInventoryFqdnComp $strHost;
	if ($objESXi -and ($objESXi.arm_id -gt 0)) {
		#Все есть! Круть!
		$intArm=[int]($objESXi.arm_id);
	} else {
		#нету ножек - нет варенья
		$intArm=$false
		errorLog "HOST: $($strHost) без АРМ в инвентори!"
	}

	#$objComp;	

	#spooLog "parsing $($strFullName) ..."
    

	#тут короче такая логика, мы узнаем, есть ли эта машина в базе
	#если она есть, то мы смотрим, есть ли по ней данные от скрипта из ОС (более полный набор)
	#если есть, то мы просто помещаем ее в тот, АРМ, на хосте которого она крутится
	#если нет, то мы полностью отправляем информацию о ней
	if ( -not $objComp) {
        	debugLog "getting $($strFullName) from inventory"
		$objComp = getInventoryFqdnComp $strFullName
	}


	#если компа нет, или он есть, но 
	#скрипт обновлявший его содержит префикс powercli 
	#или нет скрипта
	if (    `		
		(-not ($objComp -is [Object])) `
		-or `
		(($objComp -is [Object]) -and (`
			([string]($objComp.raw_version)).contains("powercli")`
			-or `
			(([string]($objComp.raw_version)).trim().Length -eq 0)`
		))`
	) {
		$strCpu="{`"processor`": {`"model`":`"$($VMware_vendor)`",`"cores`":`"$($VM.NumCpu)`"}}"
		$strMem="{`"memorybank`": {`"manufacturer`":`"$($VMware_vendor)`",`"capacity`":`"$($VM.MemoryGB*1024)`",`"serial`":`"`"}}"
		$strDisks=""
		foreach ($VMDisk in $VM.Guest.disks) {
			$strdisks="$($strDisks),{`"harddisk`":{`"model`":`"VMware Virtual disk SCSI Disk Device`",`"size`":`"$([math]::Round($VMDisk.CapacityGB))`"}}"
		}
		$strOS=$VMGuest.OSFullName
        if ( -not $strOS ) {
			errorLog "VM: $($strComp) ($($_.Name) : $($uuid) : $($arrIPv4 -join ' ')) нет типа ОС (Linux/Windows) в VMWare (без него не могу добавить в инвентори, обнови VMWare tools)"
			return
        }

		#вытаскиваем из всех IP адресов только IPv4
		$arrIPv4=@();
		foreach ($IP in $VMGuest.IPAddress) {
			if ($IP -match "^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$") {$arrIPv4 += $IP}
		}

		$arrMacs=@();
		foreach ($Nic in $VMGuest.Nics) {
			$arrMacs += $Nic.MacAddress;
		}

		$strIfaces=$arrIPv4 -join "`n"
		$strIfacesMacs=$arrMacs -join "`n"
		$data=@{
			name=[System.Web.HttpUtility]::UrlEncode($strFullName);
			os=[System.Web.HttpUtility]::UrlEncode($strOS);
			raw_hw=[System.Web.HttpUtility]::UrlEncode("$($strCpu),$($strMem)$($strDisks)");
			ignore_hw=1;
			raw_soft="";
			raw_version=[System.Web.HttpUtility]::UrlEncode($lib_version);
			ip=[System.Web.HttpUtility]::UrlEncode($strIfaces);
			mac=[System.Web.HttpUtility]::UrlEncode($strIfacesMacs);
			external_links=$(@{'VMWare.UUID'=$uuid}|ConvertTo-Json);
		}
	} else {
		$data=@{
			ignore_hw=1;
			external_links=$(@{'VMWare.UUID'=$uuid}|ConvertTo-Json);
		}
	}

	#если знаем ОС в инвентори
	if ($objComp) {
		$data["id"]=$objComp.id;
	} 

	#если нашли текущий АРМ - закрепляем
	if ($intArm) {
		$data["arm_id"]=$intArm;
	} 

	#$data

	#ОС есть в БД, она обновлена не этим скриптом и мы знаем в какой АРМ ее положить
	$logPrefix="VM: $($strFullName)".PadRight(30," ")
	if ($objComp -and $intArm -and ( -not  ([string]($objComp.raw_version)).contains("powercli"))) {
		setInventoryData 'comps' $data | out-null
		spooLog "$logPrefix - OK (arm update only)"
	} elseif ($objComp) {
		setInventoryData 'comps' $data | out-null
		spooLog "$logPrefix - OK (update)"
	} elseif ($strIfaces.Length -ge 7) {
		pushInventoryData 'comps' $data | out-null
		spooLog "$logPrefix - OK (new OS)"
	} else {
		spooLog "$logPrefix - Skipped (new VM without IP)"
	}
}


function connectVCenter() {
	param
	(
		[string]$VcenterServer,
		[string]$VcenterUser,
		[string]$VcenterPassword
	)
	spooLog "Connecting $($VcenterServer) ... "
	$Server= Connect-VIServer -server $VcenterServer -protocol https -User $VcenterUser -Password $VcenterPassword -force
	if (!$Server -or !$Server.isConnected) {
		errorLog "VSphere $($VcenterServer) connetion error"
		return
	}
	spooLog "OK"
}

#грузим VM если она включена и не спит (ОС запущена, стутус vmtools - running)
function loadVM($VM) {
    if ( -not $VM) {
        return;
    }
	if ($VM.PowerState -eq 'PoweredOn' ) {
        $uuid=getVMUUID $VM;
    
        if ( $($vm | Get-HardDisk).Count -eq 0 ) {
            spooLog "VM: $($VM.Name) : $($uuid) : no HDD in VM - skip inventorying"
            return;
        }

        $VMGuest=Get-VMGuest $VM;
        if ($VMGuest -and ($VMGuest.State -eq 'Running')) {
	    	$global:VMLIST+=$VM;
		    $global:VMGuests[$uuid]=Get-VMGuest $VM;
        } else {
            errorLog "VM: $($VM.Name) : $($uuid) : VMTools not running  ($($VMGuest.State))"
        }
	} else {
		debugLog "Powered off ($($VM.PowerState))"
	}
}

function parseVCenter() {
	param
	(
		[string]$VmName=''
	)
	if ($VmName.length) {
		spooLog "Loading VM $($VmName)..."
		loadVM (get-VM $VmName)
		$VM=get-VM $VmName;
		spooLog "OK"

		#spooLog "Loading VMHost $($VM.VMHost.name)..."
		#$VMhosts = Get-VMHost $VM.VMHost.name | Select-Object name,ProcessorType,NumCpu,Manufacturer,Model,MemoryTotalMB,Version,NetworkInfo,ConnectionState,Uid
		#spooLog "OK"

	} else {
		spooLog "Getting Online VMs..."
		foreach( $VM in (get-VM)) {
			loadVM($VM);
		}
		spooLog "OK"

		spooLog "Loading VMHosts ..."
		#собираем хосты
		$VMhosts = Get-VMHost | Select-Object name,ProcessorType,NumCpu,Manufacturer,Model,MemoryTotalMB,Version,NetworkInfo,ConnectionState,Uid
		spooLog "OK"

		spooLog "Loading VMHosts interfaces ..."
		#собираем интерфейсы:
		$VMifaces = Get-VMHostNetworkAdapter | Select-Object VMhost, IP, MAC
		spooLog "OK"

		spooLog "Parsing Online VMHosts..."
		foreach ($VMhost in $VMhosts)  {
			if ($VMhost.ConnectionState -eq 'Connected') {
				pushVMHostData $VMhost $VMifaces
			}
		}
		spooLog "OK"
	}





	#Если сделать дисконнект, то сохраненные в памяти переменные не смогут обращаться к связанным объектам.
	#Например обращение $VM.VMHost дает ничего, если коннект бн
	#Disconnect-VIServer -server $Server -force  -confirm:$false |Out-Null
	spooLog "Vcenter server $($VcenterServer) complete."
}

#Найти в кэше гостевую ОС для этой ВМ 
function getCachedVmGuest() {
	param($VM)
    $uuid=getVMUUID $VM;
	return $global:VMGuests[$uuid];
}

#получить Hostname для этой ВМ
function getVMHostname() {
	param($VM)
	return $(getCachedVmGuest $VM).HostName;
}

#получить IP адреса для этой ВМ
function getVMIps() {
	param($VM)
	$VMGuest=getCachedVmGuest $VM;

	$arrIPv4=@();
	foreach ($IP in $VMGuest.IPAddress) {
		if ($IP -match "^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$") {$arrIPv4 += $IP}
	}

    return $arrIPv4;
}




#посчитать 
function countVMsHostname() {
	param(
		[string]$hostname
	)
	$hostname=$hostname.ToLower();
	$count=0;
	foreach ($vm in $global:VMLIST) {
        $VMhostname=getVMHostname $vm;
		if ($VMhostname -and ($hostname -eq $VMhostname.ToLower())) {
			$count++;
		}
	}
	return $count;
}


#посчитать 
function countVMsHostnameIp() {
	param(
		[string]$hostname,
        $ips
	)
	$hostname=$hostname.ToLower();
	$count=0;
	:vms foreach ($vm in $global:VMLIST) {
        $VMhostname=getVMHostname $vm;
		if ($VMhostname -and ($hostname -eq $VMhostname.ToLower())) {
            $VMips = getVMIps $vm;
            foreach ($ip in $ips) {
                if ( -not ($VMips -contains $ip)) {
                    continue vms;
                }
            }
			$count++;
		}
	}
	return $count;
}


function getVMUUID($vm) {
    return "$($vm.PersistentId)@$($vm.Uid.Substring($vm.Uid.IndexOf('@')+1).Split(":")[0])"
}

function getVMhostUUID($vmhost) {
    return "$( (Get-VMhost $vmhost.name |Get-View).hardware.systeminfo.uuid )@$($vmhost.Uid.Substring($vmhost.Uid.IndexOf('@')+1).Split(":")[0])"
}