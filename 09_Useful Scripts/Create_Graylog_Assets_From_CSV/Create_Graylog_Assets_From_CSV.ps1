 $assetFile = "asset_data.csv"
 $assetData = Import-Csv -Path $assetFile -Delimiter ";"
 $targetSystem = "your.graylog.local"
 $cred = Get-Credential

 foreach ($asset in $assetData) {

    $Body = @{
        name = $asset.ID
        category = @("open")
        priority = 1 
        details = @{
            type = "machine"
            owner = $asset.Hauptbenutzer
            hostnames = @($asset.Name)
            ip_addresses = @($asset.'IP-Adresse')
            description = "Letzter Scan: " + $asset.'Letzter Scan'
            custom_fields = @{
                Betriebssystem = @{
                    type = "STRING"
                    values = @($asset.Betriebssystem)
                }

                Inventarnummer = @{
                    type = "STRING"
                    values = @($asset.Inventarnummer)
                    }

                Seriennummer = @{
                    type = "STRING"
                    values = @($asset.Seriennummer)
                }

                Status = @{
                    type = "STRING"
                    values = @($asset.Status)
                }

                Standort = @{
                    type = "STRING"
                    values = @($asset.Standort)
                }

                Organisationseinheit = @{
                    type = "STRING"
                    values = @($asset.Organisationseinheit)
                }
                
                Kostenstelle = @{
                    type = "STRING"
                    values = @($asset.Kostenstelle)
                }

                Computerrolle = @{
                    type = "STRING"
                    values = @($asset.Computerrolle)
                }
            }   
        }         
    }

    $Body = ConvertTo-Json -InputObject $Body -Depth 10

    Invoke-RestMethod `
        -Uri "http://$targetSystem/api/plugins/org.graylog.plugins.securityapp.asset/assets" `
        -Credential $cred `
        -Method Post `
        -ContentType application/json `        -Headers @{ 'X-Requested-By' = "$hostname" } `
        -Body $Body
}