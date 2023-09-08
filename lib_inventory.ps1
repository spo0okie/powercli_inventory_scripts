Add-Type -AssemblyName System.Web
#отправляет данные в инвентаризацию
#запись данных о пользователе в БД
function sendInventoryData() {
	param
	(
		[string]$uri,
		[string]$data,
		[string]$method
	)
	#$value=[System.Web.HttpUtility]::UrlEncode($value)

	#Write-Host 
	if ($global:write_inventory) {
		try { 
			$result = Invoke-WebRequest -Uri $uri -Method $method -Body $data -UseBasicParsing
			if (@(200,201) -contains $result.StatusCode) {
				debugLog("$($method): $uri - OK")
				return ($result.content | convertFrom-Json)
			} else {
				errorLog("code $($result.StatusCode) while $method-ing `"$uri`": $($result.StatusDescrition) //DATA:$($data)")
				return $false
			}
		} catch {
			$responseStream = $response.GetResponseStream()
			$streamReader = New-Object System.IO.StreamReader $responseStream
			$body = $streamReader.ReadToEnd()
			errorLog("$method-ing `"$uri`": $($_.Exception.Response.StatusCode.Value__): $($_.Exception.Message) // $($_.Exception.Message)`n$(httpResponseDebugData $response $body)`n//DATA:$($data)")
			return $false
		}
	} else {
		Write-Host RO MODE: Skip $method $uri
		Write-Host $([System.Web.HttpUtility]::UrlDecode($data.replace("&","`n")))
	}
}



function httpResponseDebugData() {
	param
	(
		[object]$reponse,
		[string]$body=''
	)
	$debugMsg= -join(
		"Response Headers:`n",
		'Status'.PadLeft(30," "), ':', "$([int]$response.StatusCode) - $($response.StatusCode)"
	)

	foreach ($HeaderKey in $response.Headers) {
		if ($HeaderKey -ne "Date" ) {
			$debugMsg = -join (
				$debugMsg , "`n",
				$HeaderKey.PadLeft(30," "),
				':',
				$response.Headers[$HeaderKey]
			)
		}							
	}
	$debugMsg = -join (
		$debugMsg , "`n",
		"$('Body'.PadLeft(30," "))`:$body"
	)

	return $debugMsg
}


#просто возвращает данные из инвентаризации запрошенные по УРЛ
function getInventoryData() {
	param
	(
		[string]$webReq
	)

	#пробуем найти запрошенные данные
	try { 
		$request = [System.Net.WebRequest]::Create($webReq)
		$response = $request.GetResponse()		
		$responseStream = $response.GetResponseStream()
		$streamReader = New-Object System.IO.StreamReader $responseStream
		$body = $streamReader.ReadToEnd()
		debugLog("GET $webReq - OK ($($response.StatusCode.Value__))`n$(httpResponseDebugData $response $body)")
		return ($body | convertFrom-Json)
	} catch [System.Net.WebException] {			  
		$response = $_.Exception.Response
		if ($response -eq $null) {
			Write-host $_.Exception
			errorLog $_.Exception.Message
			return $false
		} else {
			$responseStream = $response.GetResponseStream()
			$streamReader = New-Object System.IO.StreamReader $responseStream
			$body = $streamReader.ReadToEnd()
			if ($_.Exception.Response.StatusCode.Value__ -eq 404) {
				errorLog("GET $($webReq) - ERR $($_.Exception.Response.StatusCode.Value__) // Not found")
			} else {
				errorLog("GET $($webReq) - ERR $($_.Exception.Response.StatusCode.Value__) // $($_.Exception.Message)`n$(httpResponseDebugData $response $body)")
			}
			return $false
		}					
	} catch {			
		debugLog($_.Exception)
		#неудача!
		#spooLog("$($webReq) Error: $($_.Exception.Response.StatusCode.Value__): $($_.Exception.Message)")
		#$err=$_.Exception.Response.StatusCode.Value__
		return $false
	}
}

#возвращает ID объекта по УРЛ
function getInventoryDataId() {
	param
	(
		[string]$webReq
	)
	$obj=getInventoryData($webReq)
	#varDump($obj)
	if ($obj -eq $false) {
		return -1
	}
	#Write-Host -ForegroundColor Yellow $obj.id
	return $obj.id
}

#возвращает ID по модели(типу данных) и ее имени
function getInventoryObj() {
	param
	(
		[string]$model,
		[string]$name
	)
	return getInventoryData("$($global:inventory_RESTapi_URL)/$model/$name")
}

#возвращает ID по модели(типу данных) и ее имени
function getInventoryId() {
	param
	(
		[string]$model,
		[string]$name
	)
	if ($name.length -le 0) {
		return -1
	}
	return getInventoryDataId("$($global:inventory_RESTapi_URL)/$model/$name")
}


#устанавливает модели(типу данных) с указанным ID набор значений
#надо отметить, что набор значений должен быть достаточным для создания нового экземпляра
#иначе данными можно будет только обновлять имеющуюся модель
function setInventoryData() {
	param
	(
		[string]$model,
		[string]$id,
		[string]$data
	)
	if ([int]$id -gt 0) {
		#ИД есть - обновляем
		return sendInventoryData "$($global:inventory_RESTapi_URL)/$model/$id"	$data	"PUT"
	} else {
		#ИД не найден - создаем
		return sendInventoryData "$($global:inventory_RESTapi_URL)/$model"	$data	"POST"
	}
}

#возвращает объект компа в инвентаризации по FQDN
function getInventoryFqdnComp($fqdn) {
	if ( -not $fqdn) {
		return $false
	}

	#разбираем FQDN на хостнейм и домен
	if ($fqdn.split('.').count -gt 1 ) {
		$strComp=$fqdn.split('.')[0]
		$strDomain=$fqdn.split('.')[1]
	} else {
		$strComp=$fqdn
		$strDomain=$inventory_defaultDomain
	}

	return getInventoryObj 'comps' "$($strDomain)/$($strComp)"
}