using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

function RegenerateKey($keyId, $providerAddress){
    Write-Host "Regenerating key. Id: $keyId Resource Id: $providerAddress"
    
    $storageAccountName = ($providerAddress -split '/')[8]
    $resourceGroupName = ($providerAddress -split '/')[4]
    
    #Regenerate key 
    New-AzStorageAccountKey -ResourceGroupName $resourceGroupName -Name $storageAccountName -KeyName $keyId
    $newKeyValue = (Get-AzStorageAccountKey -ResourceGroupName $resourceGroupName -AccountName $storageAccountName|where KeyName -eq $keyId).value

    return $newKeyValue
}

function AddSecretToKeyVault($keyVAultName,$secretName,$newAccessKeyValue,$exprityDates){
    
    
    $secretvalue = ConvertTo-SecureString "$newAccessKeyValue" -AsPlainText -Force
    Set-AzKeyVaultSecret -VaultName $keyVAultName -Name $secretName -SecretValue $secretvalue  -Expires $expiryDate

}

function GetAlternateCredentialId($keyId){
    $validCredentialIdsRegEx = 'key[1-2]'
    
    If($keyId -NotMatch $validCredentialIdsRegEx){
        throw "Invalid credential id: $keyId. Credential id must follow this pattern:$validCredentialIdsRegEx"
    }
    If($keyId -eq 'key1'){
        return "key2"
    }
    Else{
        return "key1"
    }
}

function RoatateSecret($keyVaultName,$secretName){
          
    

    # Create new Application secrets
    $startDate = Get-Date
    $endDate = $startDate.AddYears(3)
    $aadAppsecret01 = New-AzureADApplicationPasswordCredential -ObjectId a1e0aee5-0c6a-4c20-b25b-563ee7ad0828 -CustomKeyIdentifier "KeyCloak" -StartDate $startDate -EndDate $endDate
    
    #Retrieve Secret
    Write-Host "Secret Retrieved"    
    Write-Host "Secret value: $aadAppsecret01"

    
    AddSecretToKeyVault $keyVAultName $secretName $aadAppsecret01 $endDate 

    Write-Host "New access key added to Key Vault. Secret Name: $secretName"
}


# Write to the Azure Functions log stream.
Write-Host "HTTP trigger function processed a request."

Try{
    #Validate request paramaters
    $keyVAultName = $Request.Query.KeyVaultName
    $secretName = $Request.Query.SecretName
    if (-not $keyVAultName -or -not $secretName ) {
        $status = [HttpStatusCode]::BadRequest
        $body = "Please pass a KeyVaultName and SecretName on the query string"
        break
    }
    
    Write-Host "Key Vault Name: $keyVAultName"
    Write-Host "Secret Name: $secretName"
    
    #Rotate secret
    Write-Host "Rotation started. Secret Name: $secretName"
    RoatateSecret $keyVAultName $secretName

    $status = [HttpStatusCode]::Ok
    $body = "Secret Rotated Successfully"
     
}
Catch{
    $status = [HttpStatusCode]::InternalServerError
    $body = "Error during secret rotation"
    Write-Error "Secret Rotation Failed: $_.Exception.Message"
}
Finally
{
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = $status
        Body = $body
    })
}

