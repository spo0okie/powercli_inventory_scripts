param(
	[string]$vcenter,
	[string]$vm
)

$ScriptDir = Split-Path -parent $MyInvocation.MyCommand.Path
. $ScriptDir\lib_funcs.ps1
. $ScriptDir\lib_inventory.ps1
. $ScriptDir\lib_powercli3.ps1
. $ScriptDir\config.priv.ps1
#$DEBUG_MODE=0

$script:logfile=	"$($ScriptDir)\powercli_inventory.log"
$script:errorLogfile=	"$($ScriptDir)\powercli_inventory_error.log"
$script:errorListFile=	"$($ScriptDir)\powercli_inventory_error.lst"
$script:VMerrorListFile="$($ScriptDir)\powercli_inventory_error.VM"
$script:errorFlagFile=	"$($ScriptDir)\powercli_inventory_error.flg"

$script:scriptErrorsArray=[ordered]@{}
$script:scriptErrorsFlag=0


foreach ($item in $vCentersList) {
	$node=$item.node;		#fqdn
	$name=$node.split(".")[0];	#hostname
	if ($vcenter.length) {
		if ( ($vcenter -eq $node) -or ($vcenter -eq $name)) {
			if ($vm.length) {
				parseVCenterVm $item.node $item.login $item.password $vm
			} else {
				parseVCenter $item.node	$item.login $item.password
			}
		}
	} else {
		parseVCenter $item.node	$item.login $item.password
	}
}

exit
$scriptErrorsFlag | Out-File -filePath $errorFlagFile

$errList="";
$VMerrList="";
foreach($err in $scriptErrorsArray.GetEnumerator()) {
	$errList= -join ($errList, $err.Value,"x :",$err.Name,"`n");
	if ($err.Name.StartsWith('VM:')) {
		$VMerrList= -join ($VMerrList, $err.Value,"x :",$err.Name,"`n");
	}
}
$errList | Out-File -filePath $errorListFile -encoding Default
$VMerrList | Out-File -filePath $VMerrorListFile -encoding Default

if ($scriptErrorsFlag) {
	Log "WARNING: script complete with errors!"
	$scriptErrorsArray
} else {
	Log "Script complete with no errors."
}