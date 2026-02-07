 $assetFile = "asset_data.csv"
 $assetData = Import-Csv -Path $assetFile -Delimiter ";" -Encoding UTF8
 $targetSystem = "siem.fritzdata.de"
 $cred = Get-Credential

 foreach ($asset in $assetData) {

    $Body = @{
        name = $asset.AssetName
        category = @("Production", "Server", $asset.ComputerRole, $asset.MachineType)
        priority = 1 
        details = @{
            type = "machine"
            owner = $asset.Owner
            hostnames = @($asset.AssetName)
            ip_addresses = @($asset.'IpAddress')
            description = "Letzter Scan: " + $asset.'LastScan'
            geo_info = @{
                country_name = $asset.Country
                country_iso_code = $asset.CountryCode
                city_name = $asset.City
                latitude = $asset.Latitude
                longitude = $asset.Longitude
                region = $asset.Region
                time_zone = $asset.Timezone
                }
            custom_fields = @{
                Betriebssystem = @{
                    type = "STRING"
                    values = @($asset.OperatingSystem)
                }

                Inventarnummer = @{
                    type = "NUMBER"
                    values = @($asset.InventoryNumber)
                    }

                Seriennummer = @{
                    type = "STRING"
                    values = @($asset.SerialNumber)
                }

                Status = @{
                    type = "STRING"
                    values = @($asset.Status)
                }

                Standort = @{
                    type = "STRING"
                    values = @($asset.Site)
                }

                Organisationseinheit = @{
                    type = "STRING"
                    values = @($asset.OrganizationalUnit)
                }
                
                Kostenstelle = @{
                    type = "STRING"
                    values = @($asset.CostCenter)
                }

                Computerrolle = @{
                    type = "STRING"
                    values = @($asset.ComputerRole)
                }
            }   
        }         
    }

    #echo $Body.details.custom_fields | Select-Object -Property *
    #pause
    
    $Body = ConvertTo-Json -InputObject $Body -Depth 10

    #echo $Body
    #pause


    #try {
        Invoke-RestMethod `
            -Uri "http://$targetSystem/api/plugins/org.graylog.plugins.securityapp.asset/assets" `
            -Credential $cred `
            -Method Post `
            -ContentType "application/json; charset=utf-8" `
            -Headers @{ 
                'X-Requested-By' = "$hostname"
             } `
            -Body $Body
    #}
    
    <#
    catch {
        
        $assetId= ConvertFrom-Json -InputObject $body | Select-Object -ExpandProperty name
        Write-Host -ForegroundColor Red "The Asset with the Asset ID $assetId has not been properly created"
    }
    #>
    
}