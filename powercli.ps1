param(
	[string]$vcenter,
	[string]$vm
)

$ScriptDir = Split-Path -parent $MyInvocation.MyCommand.Path
. $ScriptDir\..\libs.ps1\lib_funcs.ps1
. $ScriptDir\..\libs.ps1\lib_inventory.ps1
. $ScriptDir\lib_powercli.ps1
. $ScriptDir\config.priv.ps1
$global:DEBUG_MODE=0;
$global:InvRequestTimeout=30000;

$script:logfile=	"$($ScriptDir)\powercli_inventory.log"
$script:errorLogfile=	"$($ScriptDir)\powercli_inventory_error.log"
$script:errorListFile=	"$($ScriptDir)\powercli_inventory_error.lst"
$script:VMerrorListFile="$($ScriptDir)\powercli_inventory_error.VM"
$script:errorFlagFile=	"$($ScriptDir)\powercli_inventory_error.flg"

$script:scriptErrorsArray=[ordered]@{}
$script:scriptErrorsFlag=0;

$global:skip404errors=$true;

$global:VMLIST=@();
$global:VMGuests=@{};



spooLog "Loading inventory data...";
inventoryCacheAllComps;

spooLog "Loading VMWare data"

foreach ($item in $vCentersList) {
	$node=$item.node;		#fqdn
	$name=$node.split(".")[0];	#hostname
	if ($vcenter.length) {		#если у нас ограничение на конкретный vcenter
		if ( ($vcenter -eq $node) -or ($vcenter -eq $name)) {			
			connectVCenter $item.node $item.login $item.password
		}
	} else {
		connectVCenter $item.node $item.login $item.password
	}
}

if ($vm.length) {
	parseVCenter $vm
} else {
	parseVCenter
}

spooLog "$( $VMLIST.length ) running VMs loaded."



$VMLIST
#$VMGuests;

foreach ($_ in $VMLIST) {
#	$_|fl;
	$hostname=getVMHostname($_);
	#$([string]$hostname).toLower();
	#if (-not(([string]$hostname).toLower() -eq 'erp-prod')) {continue};
	$uuid=getVMUUID $_;
	$invHost=searchInvByVMUUID($uuid);
	if ($invHost -eq $false ){
		$VMcount=countVMsHostname($hostname);
		$Invcount=countInventoryFqdnComps($hostname);
		#spooLog "$hostname : $VMcount : $Invcount"
		#у нас одна такая ВМ и не более одного узла в инвентори
		if (($VMcount -eq 1) -and ($Invcount -le 1)) {
			pushVMData ($_);
		} else {
			$ips = getVMIps $_;
			if ($ips.length -gt 0) {
				$VMcount=countVMsHostnameIp $hostname $ips;
				$Invcount=countInventoryFqdnIPComps $hostname $ips;
				if (($VMcount -eq 1) -and ($Invcount -eq 1)) {
					pushVMData $_ $(getInventoryFqdnIpComp $hostname $ips);
				} else {
					if ( -not $hostname) {$hostname='<no hostname>'}
					errorLog "VM: $($hostname) (VM: $($_.Name); UUID: $($uuid); IPS: $($ips -join ' ')) не найдена в инвентори по UUID, и не идентифицируется по hostname+IP ($VMcount ВМ, $Invcount ОС)"
				}
			} else {
				if ( -not $hostname) {$hostname='<no hostname>'}
				errorLog "VM: $($hostname) (VM: $($_.Name); UUID: $($uuid); IPS: <missing>) не найдена в инвентори по UUID, и не идентифицируется по hostname ($VMcount ВМ, $Invcount ОС)"              	
			}
		}
	} else {
		debugLog "$hostname found by VM UUID"
		pushVMData $_ $invHost;
	}
}


Disconnect-VIServer -server * -force  -confirm:$false |Out-Null


$scriptErrorsFlag | Out-File -filePath $errorFlagFile

$errList=@();
$VMerrList=@();
foreach($err in $scriptErrorsArray.GetEnumerator()) {
	$errList+= -join ($err.Value,"x :",$err.Name);
	if ($err.Name.StartsWith('VM:')) {
		$VMerrList+= -join ($err.Value,"x :",$err.Name);
	}
}

$($errList | Sort-Object)   -join "`n" | Out-File -filePath $errorListFile -encoding Default
$($VMerrList | Sort-Object) -join "`n" | Out-File -filePath $VMerrorListFile -encoding Default

if ($scriptErrorsFlag) {
	spooLog "WARNING: script complete with errors!"
	$scriptErrorsArray
} else {
	spooLog "Script complete with no errors."
}