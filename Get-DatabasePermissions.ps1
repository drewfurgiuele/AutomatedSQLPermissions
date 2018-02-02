[CmdletBinding()]
Param (
    [parameter(Mandatory=$true)] 
    [string] $servername,
	[parameter(Mandatory = $false)]
	[string]$repoServerName,
	[parameter(Mandatory = $false)]
	[string]$repoinstancename="DEFAULT",
	[parameter(Mandatory = $true)]
	[string]$repodatabasename

)

$captureDateTime = Get-Date

$InstanceName = $null
if ($ServerName.Contains("\")) {
    $InstanceName = $ServerName.Split("\")[1]
} else {
    $InstanceName = 'DEFAULT'
}

Write-Verbose "Creating scripting object..."
$scripter = New-Object Microsoft.SQLServer.Management.Smo.Scripter $serverName
$scripter.Options.IncludeIfNotExists = $true

Write-Verbose "Getting databases..."
if ($InstanceName -eq "DEFAULT")
{
    $databases = Get-ChildItem -Path SQLSERVER:\SQL\$servername\$instancename\Databases
} else {
    $databases = Get-ChildItem -Path SQLSERVER:\SQL\$servername\Databases
}

Write-Verbose "Creating data tables..."
$captureTable = New-Object System.Data.DataTable
$captureTable.Columns.Add("CaptureID", [System.Guid]) | Out-Null
$captureTable.Columns.Add("CaptureDateTime") | Out-Null
$captureTable.Columns.Add("ServerName") | Out-Null
$captureTable.Columns.Add("InstanceName") | Out-Null
$captureTable.Columns.Add("DatabaseName") | Out-Null


$userTable = New-Object System.Data.DataTable
$userTable.Columns.Add("CaptureID", [System.Guid]) | Out-Null
$userTable.Columns.Add("UserName") | Out-Null
$userTable.Columns.Add("CreateScript") | Out-Null

$rolesTable = New-Object System.Data.DataTable
$rolesTable.Columns.Add("CaptureID", [System.Guid]) | Out-Null
$rolesTable.Columns.Add("RoleName") | Out-Null
$rolesTable.Columns.Add("RoleMember") | Out-Null
$rolesTable.Columns.Add("CreateScript") | Out-Null

$objectTable = New-Object System.Data.DataTable
$objectTable.Columns.Add("CaptureID", [System.Guid]) | Out-Null
$objectTable.Columns.Add("ObjectClass") | Out-Null
$objectTable.Columns.Add("ObjectSchema") | Out-Null
$objectTable.Columns.Add("ObjectName") | Out-Null
$objectTable.Columns.Add("PermissionState") | Out-Null
$objectTable.Columns.Add("PermissionType") | Out-Null
$objectTable.Columns.Add("Grantee") | Out-Null


ForEach ($d in $databases) {
    $databaseName = $d.Name
    Write-Verbose "Working in database $databasename..."

    $captureGuid = New-Guid
    Write-Verbose "Creating capture record $captureGuid..."

    $row = $captureTable.NewRow()
    $row["CaptureID"] = $captureGuid
    $row["CaptureDateTime"] = $captureDateTime
    $row["ServerName"] = $servername
    $row["InstanceName"] = $instanceName
    $row["DatabaseName"] = $d.Name
    $captureTable.Rows.Add($row)

    Write-Verbose "Scripting database users..."
    $dbusers = $d.Users
    ForEach ($u in $dbusers) {
        $row = $userTable.NewRow()
        $row["CaptureID"] = $captureGuid
        $row["UserName"] = $u.Name
        $row["CreateScript"] = [string] $scripter.Script($u)
        $userTable.Rows.Add($row)
    }

    Write-Verbose "Capturing role members..."
    $dbRoles = $d.Roles
    ForEach ($r in $dbRoles){
        $roleMembers = $r.EnumMembers()
        ForEach ($m in $roleMembers) {
            $row = $rolesTable.NewRow()
            $row["CaptureID"] = $captureGuid
            $row["RoleName"] = $r
            $row["RoleMember"] = $m
            $rolesTable.Rows.Add($row)
        }
    }

    Write-Verbose "Capturing database permissions..."    
    $dbPermissions = $d.EnumDatabasePermissions()
    ForEach ($p in $dbPermissions) {
            $row = $objectTable.NewRow()
            $row["CaptureID"] = $captureGuid
            $row["ObjectClass"] = "Database"
            $row["ObjectSchema"] = $null
            $row["ObjectName"] = $p.ObjectName
            $row["PermissionState"] = $p.PermissionState.ToString()
            $row["PermissionType"] = $p.PermissionType.ToString()
            $row["Grantee"] = $p.Grantee
            $objectTable.Rows.Add($row)
    }

    Write-Verbose "Capturing object permissions..."        
    $objectPermissions = $d.EnumObjectPermissions()
    ForEach ($p in $objectPermissions) {
            $row = $objectTable.NewRow()
            $row["CaptureID"] = $captureGuid
            $row["ObjectClass"] = $p.ObjectClass.ToString()
            $row["ObjectSchema"] = $p.ObjectSchema
            $row["ObjectName"] = $p.ObjectName
            $row["PermissionState"] = $p.PermissionState.ToString()
            $row["PermissionType"] = $p.PermissionType.ToString()
            $row["Grantee"] = $p.Grantee
            $objectTable.Rows.Add($row)
    }
}  

$adminConnection = New-Object System.Data.SqlClient.SqlConnection
if ($repoInstanceName -ne "DEFAULT") { $repoServerName = "$repoServerName\$repoInstanceName" }
$adminConnectionString = "Server={0};Database={1};Trusted_Connection=True;Connection Timeout=15" -f $repoServerName,$repoDatabaseName

Write-Verbose "Writing capture information to repository database..."    
$bcp = New-Object System.Data.SqlClient.SqlBulkCopy($adminConnectionString)
$bcp.DestinationTableName = "Permissions.Captures"
$bcp.BatchSize = 1000
ForEach ($Column in $captureTable.Columns)
{
    [void]$bcp.ColumnMappings.Add($Column.ColumnName, $Column.ColumnName)    
}
$bcp.WriteToServer($captureTable)        

Write-Verbose "Writing user information to repository database..."    
$bcp = New-Object System.Data.SqlClient.SqlBulkCopy($adminConnectionString)
$bcp.DestinationTableName = "Permissions.DatabaseUsers"
$bcp.BatchSize = 1000
ForEach ($Column in $userTable.Columns)
{
    [void]$bcp.ColumnMappings.Add($Column.ColumnName, $Column.ColumnName)    
}
$bcp.WriteToServer($userTable)      

Write-Verbose "Writing role information to repository database..."    
$bcp = New-Object System.Data.SqlClient.SqlBulkCopy($adminConnectionString)
$bcp.DestinationTableName = "Permissions.DatabaseRoleMembers"
$bcp.BatchSize = 1000
ForEach ($Column in $rolesTable.Columns)
{
    [void]$bcp.ColumnMappings.Add($Column.ColumnName, $Column.ColumnName)    
}
$bcp.WriteToServer($rolesTable)      

Write-Verbose "Writing object and database permission information to repository database..."    
$bcp = New-Object System.Data.SqlClient.SqlBulkCopy($adminConnectionString)
$bcp.DestinationTableName = "Permissions.DatabaseObjectPermissions"
$bcp.BatchSize = 1000
ForEach ($Column in $objectTable.Columns)
{
    [void]$bcp.ColumnMappings.Add($Column.ColumnName, $Column.ColumnName)    
}
$bcp.WriteToServer($objectTable)