#Текущее время в UTC
function getUTCNow() {
    return (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss")
}


function varDump() {
    param (
        [object]$var
    )
    Write-Host -ForegroundColor Magenta ($var | Format-List | Out-String)
}


#выводит сообщение в лог файл
#пришлось взять идиотское название, т.к. в каком-то месте у меня вызов Log както конфликтнул с 
#Get-Log от VMWare
function spooLog()
{
	param
	(
		[string]$msg,
		[boolean]$show_date = $true
	)
	if ($show_date) {
		$now=Get-Date
	}
	if ($global:logfile) {
		"$now $msg" | Out-File -filePath "$global:logfile" -append -encoding Default
	}
	Write-Host $now $msg
}

#для совместимости оставим это, чтобы не переписывать все остальные скрипты, которым не нужен VMWare
function Log()
{
	param
	(
		[string]$msg,
		[boolean]$show_date = $true
	)
	spooLog $msg $show_date
}


#выводит сообщение об ошибке в лог файл
function errorLog()
{
	param
	(
		[string]$msg,
		[boolean]$show_date = $true
	)

	if ($show_date) {
		$now=Get-Date
	}

	#если логфайл есть, то пишем его
	if ($global:logfile) {
		"$now ERROR: $msg" | Out-File -filePath "$global:logfile" -append -encoding Default
	}

	#если есть логфайл для ошибок - пишем его
	if ($global:errorLogfile) {
		"$now $msg" | Out-File -filePath "$global:errorLogfile" -append -encoding Default
	}


	#выставляем флажок что была ошибка
	$global:scriptErrorsFlag = 1

	Write-Host -foregroundColor red $now "ERROR:" $msg

	#если есть массив ошибок - добавляем в него
	if (Test-Path variable:global:scriptErrorsArray) {
		$global:scriptErrorsArray[$msg]++;

		#$md5 = New-Object -TypeName System.Security.Cryptography.MD5CryptoServiceProvider
		#$utf8 = New-Object -TypeName System.Text.UTF8Encoding
		#$hash = ([System.BitConverter]::ToString($md5.ComputeHash($utf8.GetBytes($msg)))).replace("-","").ToLower()

		#Write-Host -foregroundColor blue "Errors count:", $global:scriptErrorsArray.length
		#for ($i = 0; $i -le ($global:scriptErrorsArray.length - 1); $i ++) {
		#	if ($global:scriptErrorsArray[$i].hash -eq $hash) {
		#		$global:scriptErrorsArray[$i].count++;
		#		return
		#	}
		#}
		#$global:scriptErrorsArray+=@{
		#	msg=$msg
		#	hash=$hash
		#	count=1
		#};
		#Write-Host -foregroundColor blue "Errors count:", $global:scriptErrorsArray.length
    	}
}

#выводит сообщение об ошибке в лог файл
function warningLog()
{
	param
	(
		[string]$msg,
		[boolean]$show_date = $true
	)

	if ($show_date) {
		$now=Get-Date
	}

    #если логфайл есть, то пишем его
	if ($global:logfile) {
		"$now WARNING: $msg" | Out-File -filePath "$global:logfile" -append -encoding Default
	}

    #если есть логфайл для ошибок - пишем его
	if ($global:warningLogfile) {
		"$now $msg" | Out-File -filePath "$global:warningLogfile" -append -encoding Default
	}

    #если есть массив ошибок - добавляем в него
    if ($global:scriptWarningsArray) {
        $global:scriptWarningsArray += $msg
    }

    #выставляем флажок что была ошибка
    $global:scriptWarningsFlag = 1

	Write-Host -foregroundColor Yellow $now "WARNING:" $msg
}


#выводит сообщение об ошибке в лог файл
function debugLog()
{
	param
	(
		[string]$msg
	)

	if ($global:DEBUG_MODE -and $global:DEBUG_MODE -gt 0) {
        spooLog $msg
    }
}



function New-SWRandomPassword {
    <#
    .Synopsis
       Generates one or more complex passwords designed to fulfill the requirements for Active Directory
    .DESCRIPTION
       Generates one or more complex passwords designed to fulfill the requirements for Active Directory
    .EXAMPLE
       New-SWRandomPassword
       C&3SX6Kn

       Will generate one password with a length between 8  and 12 chars.
    .EXAMPLE
       New-SWRandomPassword -MinPasswordLength 8 -MaxPasswordLength 12 -Count 4
       7d&5cnaB
       !Bh776T"Fw
       9"C"RxKcY
       %mtM7#9LQ9h

       Will generate four passwords, each with a length of between 8 and 12 chars.
    .EXAMPLE
       New-SWRandomPassword -InputStrings abc, ABC, 123 -PasswordLength 4
       3ABa

       Generates a password with a length of 4 containing atleast one char from each InputString
    .EXAMPLE
       New-SWRandomPassword -InputStrings abc, ABC, 123 -PasswordLength 4 -FirstChar abcdefghijkmnpqrstuvwxyzABCEFGHJKLMNPQRSTUVWXYZ
       3ABa

       Generates a password with a length of 4 containing atleast one char from each InputString that will start with a letter from 
       the string specified with the parameter FirstChar
    .OUTPUTS
       [String]
    .NOTES
       Written by Simon W?hlin, blog.simonw.se
       I take no responsibility for any issues caused by this script.
    .FUNCTIONALITY
       Generates random passwords
    .LINK
       http://blog.simonw.se/powershell-generating-random-password-for-active-directory/
   
    #>
    [CmdletBinding(DefaultParameterSetName='FixedLength',ConfirmImpact='None')]
    [OutputType([String])]
    Param
    (
        # Specifies minimum password length
        [Parameter(Mandatory=$false,
                   ParameterSetName='RandomLength')]
        [ValidateScript({$_ -gt 0})]
        [Alias('Min')] 
        [int]$MinPasswordLength = 8,
        
        # Specifies maximum password length
        [Parameter(Mandatory=$false,
                   ParameterSetName='RandomLength')]
        [ValidateScript({
                if($_ -ge $MinPasswordLength){$true}
                else{Throw 'Max value cannot be lesser than min value.'}})]
        [Alias('Max')]
        [int]$MaxPasswordLength = 12,

        # Specifies a fixed password length
        [Parameter(Mandatory=$false,
                   ParameterSetName='FixedLength')]
        [ValidateRange(1,2147483647)]
        [int]$PasswordLength = 8,
        
        # Specifies an array of strings containing charactergroups from which the password will be generated.
        # At least one char from each group (string) will be used.
        [String[]]$InputStrings = @('abcdefghijkmnpqrstuvwxyz', 'ABCEFGHJKLMNPQRSTUVWXYZ', '23456789', '!,-=(){}_.'),

        # Specifies a string containing a character group from which the first character in the password will be generated.
        # Useful for systems which requires first char in password to be alphabetic.
        [String] $FirstChar,
        
        # Specifies number of passwords to generate.
        [ValidateRange(1,2147483647)]
        [int]$Count = 1
    )
    Begin {
        Function Get-Seed{
            # Generate a seed for randomization
            $RandomBytes = New-Object -TypeName 'System.Byte[]' 4
            $Random = New-Object -TypeName 'System.Security.Cryptography.RNGCryptoServiceProvider'
            $Random.GetBytes($RandomBytes)
            [BitConverter]::ToUInt32($RandomBytes, 0)
        }
    }
    Process {
        For($iteration = 1;$iteration -le $Count; $iteration++){
            $Password = @{}
            # Create char arrays containing groups of possible chars
            [char[][]]$CharGroups = $InputStrings

            # Create char array containing all chars
            $AllChars = $CharGroups | ForEach-Object {[Char[]]$_}

            # Set password length
            if($PSCmdlet.ParameterSetName -eq 'RandomLength')
            {
                if($MinPasswordLength -eq $MaxPasswordLength) {
                    # If password length is set, use set length
                    $PasswordLength = $MinPasswordLength
                }
                else {
                    # Otherwise randomize password length
                    $PasswordLength = ((Get-Seed) % ($MaxPasswordLength + 1 - $MinPasswordLength)) + $MinPasswordLength
                }
            }

            # If FirstChar is defined, randomize first char in password from that string.
            if($PSBoundParameters.ContainsKey('FirstChar')){
                $Password.Add(0,$FirstChar[((Get-Seed) % $FirstChar.Length)])
            }
            # Randomize one char from each group
            Foreach($Group in $CharGroups) {
                if($Password.Count -lt $PasswordLength) {
                    $Index = Get-Seed
                    While ($Password.ContainsKey($Index)){
                        $Index = Get-Seed                        
                    }
                    $Password.Add($Index,$Group[((Get-Seed) % $Group.Count)])
                }
            }

            # Fill out with chars from $AllChars
            for($i=$Password.Count;$i -lt $PasswordLength;$i++) {
                $Index = Get-Seed
                While ($Password.ContainsKey($Index)){
                    $Index = Get-Seed                        
                }
                $Password.Add($Index,$AllChars[((Get-Seed) % $AllChars.Count)])
            }
            Write-Output -InputObject $(-join ($Password.GetEnumerator() | Sort-Object -Property Name | Select-Object -ExpandProperty Value))
        }
    }
}

Function TimedPrompt($prompt,$secondsToWait){	
	#чистим буфер нажатий
	while ($host.UI.RawUI.KeyAvailable) {
		$null=$host.UI.RawUI.ReadKey("NoEcho,IncludeKeyUp,IncludeKeyDown")
		start-sleep -milliseconds 50
	}
	Write-Host -NoNewline $prompt
	$secondsCounter = 0
	$subCounter = 0
	#
	While (!$host.ui.rawui.KeyAvailable){
		start-sleep -milliseconds 10
		$subCounter = $subCounter + 10
		if($subCounter -eq 1000)
		{
			$secondsCounter++
			$subCounter = 0
			Write-Host -NoNewline "."
		}		
		If ($secondsCounter -ge $secondsToWait) { 
			Write-Host "`r`n"
			while ($host.UI.RawUI.KeyAvailable) {
				$null=$host.UI.RawUI.ReadKey("NoEcho,IncludeKeyUp,IncludeKeyDown")
				start-sleep -milliseconds 50
			}
			return $false;
		}
	}
	while ($host.UI.RawUI.KeyAvailable) {
		$null=$host.UI.RawUI.ReadKey("NoEcho,IncludeKeyUp,IncludeKeyDown")
		start-sleep -milliseconds 50
	}
	Write-Host "`r`n"
	return $true;
}


#приводит телефон к виду +7(987)654-3210
function correctMobile() {
	param (
		[string]$number
	)

	#убираем пробелы и вообще все
	if ($number.Length -le 3) {
		return $number
	}

	$number=$number.Replace(' ','').Replace('-','').Replace('.','').Replace('+','')
	#Log($original+": clean ["+$number+"]")

	#проверяем что цифр 11	
	#if ( -not ($number.Replace('+','').Replace('(','').Replace(')','').Length -eq 11)) {
		#Log($original+": numbers ["+$number.Replace('+','').Replace('(','').Replace(')','')+"]")
		#Log($original+": numberscount ["+$number.Replace('+','').Replace('(','').Replace(')','').Length+"]")
	#	return $original
	#}


	#810375 -> +375XXX
	if (
		($number.Substring(0,3) -eq "810") -and
		($number.Replace(')','').Replace('(','').Length -gt 11)	
	) {
		$number=$number.Substring(3)
	}
	

	if (
		($number.Replace(')','').Replace('(','').Length -eq 11)	
	) {
		#$number.Replace(')','').Replace('(','').Length
		#8XXX -> 7XXX
		if ($number.Substring(0,1) -eq "8") {
			$number="7"+$number.Substring(1)			
		}

		#проверяем что скобочки есть и они расставлены правильно
		$leftBracket=$number.IndexOf("(")
		$rightBracket=$number.IndexOf(")")
		#$leftBracket,$rightBracket
		if ( ($leftBracket -le 0) -or ($rightBracket -le 0) -or ($rightBracket -lt $leftBracket) ) {
			#"HOHOHO"
			$number=$number.Replace('(','').Replace(')','')
			$countryCode=$number.Substring(0,1);
			$cityCode=$number.Substring(1,3);
			$localCode=$number.Substring(4);
			$number=$countryCode+'('+$cityCode+')'+$localCode
			$rightBracket=$number.IndexOf(")")
		}

		#проверяем знак тире
		$minusLeft=$number.Substring(0,$rightBracket+4)
		$minusRight=$number.Substring($rightBracket+4)
	 	$number = $minusLeft+'-'+$minusRight
	}

	return "+" + $number

}

#Разбивает строку на список телефонов через запятую
#каждому телефону проводит коррекцию написания
#собирает обратно обрезая невлезающие в 64 символа
function correctPhonesList() {
	param
	(
		[string]$nums
	)
	$arnums=$nums -split ','
	$out=@()
	for ( $i = 0; $i -lt $arnums.Count; $i++ ) {
		$num = correctMobile( $arnums[$i] )
		if ((($out -join ',').Length + $num.Length) -lt 63) {
			$out+=$num
		}
	}
	return $out -join ','
}


function setGroupByDepartment() {
	param
	(
		[string]$group,
		[string]$department,
		[string]$OUDN
	)
	#добваляем новых
	foreach ($user in Get-ADUser -Filter {department -eq $department} -SearchBase $OUDN) {
		#Write-Host -ForegroundColor green $user
		Add-ADGroupMember -Identity $group -Member $user.samaccountname -ErrorAction SilentlyContinue -Confirm:$false
	}

	#удаляем лишних
	Get-ADGroupMember -Identity $group| Where-Object { $_.objectClass -eq 'user' } | Get-ADUser -Properties * | ForEach-Object {
		if( $_.department -ne $department) {
			#Write-Host -ForegroundColor red "$( $_ ) $( $_.department )"
			Remove-ADGroupMember -Identity $group -Member $_.samaccountname -Confirm:$false
		}
	}
}

function setGroupBy2Departments() {
	param
	(
		[string]$group,
		[string]$department1,
		[string]$department2,
		[string]$OUDN
	)
	#добваляем новых
	foreach ($user in Get-ADUser -Filter {(department -eq  $department1) -or (department -eq $department2)} -SearchBase $OUDN) {
		#Write-Host -ForegroundColor green $user
		Add-ADGroupMember -Identity $group -Member $user.samaccountname -ErrorAction SilentlyContinue -Confirm:$false
	}

	#удаляем лишних
	Get-ADGroupMember -Identity $group| Where-Object { $_.objectClass -eq 'user' } | Get-ADUser -Properties * | ForEach-Object {
		if( ($_.department -ne $department1) -and ($_.department -ne $department2)) {
			#Write-Host -ForegroundColor red "$( $_ ) $( $_.department )"
			Remove-ADGroupMember -Identity $group -Member $_.samaccountname -Confirm:$false
		}
	}
}

