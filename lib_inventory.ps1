
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

	#Write-Host $method $uri
	try { 
    
		$result=Invoke-WebRequest -Uri $uri -Method $method -Body $data #-UseBasicParsing
		#Log("$($inventory_RESTapi_URL)/users/$($id)")
		#Log("Success")
		return ($result.content | convertFrom-Json)
	} catch {
		#Log("Error: $($_.Exception.Response.StatusCode.Value__): $($_.Exception.Message)")
		$_.Exception.Response
		$_.Exception.content
	}
}




#просто возвращает данные из инвентаризации запрошенные по УРЛ
function getInventoryData() {
	param
	(
		[string]$webReq
	)

	#пробуем найти запрошенные данные
	#Write-Host $webReq
	try { 
		$obj = ((invoke-WebRequest $webReq -ContentType "text/plain; charset=utf-8" -UseBasicParsing).content | convertFrom-Json)
		return $obj
	} catch {
		#неудача!
		$err=$_.Exception.Response.StatusCode.Value__
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
	if ($obj -eq $false) {
		return -1
	}
	return $obj.id
}

#возвращает ID по модели(типу данных) и ее имени
function getInventoryObj() {
	param
	(
		[string]$model,
		[string]$name
	)
	return getInventoryData("$($inventory_RESTapi_URL)/$($model)/$($name)")
}

#возвращает ID по модели(типу данных) и ее имени
function getInventoryId() {
	param
	(
		[string]$model,
		[string]$name
	)
	return getInventoryDataId("$($inventory_RESTapi_URL)/$($model)/$($name)")
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
		$result=sendInventoryData "$($inventory_RESTapi_URL)/$($model)/$($id)"	$data	"PUT"
	} else {
		#ИД не найден - создаем
		$result=sendInventoryData "$($inventory_RESTapi_URL)/$($model)"		$data	"POST"
	}
	return $result
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