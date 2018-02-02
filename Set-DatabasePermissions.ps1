[CmdletBinding(SupportsShouldProcess=$true)]
Param (
    [parameter(Mandatory=$true)] 
    [string]$servername,
	[parameter(Mandatory = $false)]
	[string]$repoServerName,
	[parameter(Mandatory = $false)]
	[string]$repoinstancename="DEFAULT",
	[parameter(Mandatory = $true)]
	[string]$repodatabasename,
	[parameter(Mandatory = $false)]
	[string]$databaseName
)


$InstanceName = $null
if ($ServerName.Contains("\")) {
    $InstanceName = $ServerName.Split("\")[1]
} else {
    $InstanceName = 'DEFAULT'
}

if ($instanceName -ne "DEFAULT") {
    $instance = Get-ChildItem -Path SQLSERVER:\SQL\$ServerName | Where-Object {$_.InstanceName -eq $InstanceName}
} else {
    $instance = Get-ChildItem -Path SQLSERVER:\SQL\$ServerName | Where-Object {$_.InstanceName -eq ""}
}

$ServerVersion = $instance.Version.Major
if ($instanceName -eq "DEFAULT") {
    $Databases = Get-ChildItem -Path SQLSERVER:\SQL\$ServerName\$InstanceName\Databases
} else {
    $Databases = Get-ChildItem -Path SQLSERVER:\SQL\$ServerName\Databases
}

$Repository = Get-ChildItem -Path SQLSERVER:\SQL\$repoServerName\$repoInstanceName\Databases | Where-Object {$_.Name -eq $repodatabasename}

if ($DatabaseName) {
    $Databases = $Databases | Where-Object {$_.Name -eq $DatabaseName}
}

ForEach ($d in $Databases) {
    $CurrentDatabase = $d.Name

    $Results = [pscustomobject] @{
	    ServerName = $ServerName
		InstanceName = $instanceName
		DatabaseName = $CurrentDatabase
        PermissionSet = $null
		TotalSuccessful = 0
		TotalError = 0
        SuccessStatements = @()
        ErrorStatements = @()
    }

    $RefreshID = ($Repository.ExecuteWithResults("SELECT TOP 1 CaptureID, CaptureDateTime, ServerName, InstanceName, DatabaseName FROM Permissions.Captures WHERE ServerName = '$servername' AND InstanceName = '$instanceName' AND DatabaseName = '$CurrentDatabase' ORDER BY CaptureDateTime DESC")).Tables[0].CaptureID
    if ($RefreshID) {
        $Results.PermissionSet = $RefreshID
        $Users = ($Repository.ExecuteWithResults("SELECT CreateScript FROM Permissions.DatabaseUsers WHERE CaptureID = '$RefreshID' ORDER BY ID")).Tables[0].CreateScript
        ForEach ($u in $users) {
            try {
                $d.ExecuteWithResults($u) | Out-Null
                $Results.TotalSuccessful++
                $Results.SuccessStatements += $u
            } catch {
                $Results.TotalError++
                $Results.ErrorStatements += $u
            }
        }

        $RoleMembers = ($Repository.ExecuteWithResults("SELECT RoleName, RoleMember FROM Permissions.DatabaseRoleMembers WHERE CaptureID = '$RefreshID' ORDER BY ID")).Tables[0]
        ForEach ($r in $RoleMembers) {
            try {
                if ($ServerVersion -gt 10) {
                    $statement = "ALTER ROLE " + $r.RoleName + " ADD MEMBER [" + $r.RoleMember + "]"
                } else {
                    $statement = "EXEC sp_addrolemember N'" + ($r.RoleName.Replace("[","").Replace("]","")) + "', N'" + ($r.RoleMember.Replace("[","").Replace("]","")) + "';"
                }
                $d.ExecuteWithResults($statement) | Out-Null
                $Results.TotalSuccessful++
                $Results.SuccessStatements += $statement
            } catch {
                $Results.TotalError++
                $Results.ErrorStatements += $statement
            }
        }

        $DatabaseLevelPermissions = ($Repository.ExecuteWithResults("SELECT ObjectName, PermissionState, PermissionType, Grantee FROM Permissions.DatabaseObjectPermissions WHERE CaptureID = '$RefreshID' AND ObjectClass = 'Database' ORDER BY ID")).Tables[0]
        ForEach ($dbl in $DatabaseLevelPermissions)
        {
            $statement = $dbl.permissionState + " " + $dbl.PermissionType + " TO [" + $dbl.Grantee + "]"
            try {
                $d.ExecuteWithResults($statement) | Out-Null
                $Results.TotalSuccessful++
                $Results.SuccessStatements += $statement
            } catch {
                $Results.TotalError++
                $Results.ErrorStatements += $statement
            }
        }

        $DatabaseObjectPermissions = ($Repository.ExecuteWithResults("SELECT ObjectName, ObjectClass, ObjectSchema, PermissionState, PermissionType, Grantee FROM Permissions.DatabaseObjectPermissions WHERE CaptureID = '$RefreshID' AND ObjectClass != 'Database' ORDER BY ID")).Tables[0]
        ForEach ($dbop in $DatabaseObjectPermissions)
        {
            switch ($dbop.ObjectClass) {
                Schema {$statement = $dbop.permissionState + " " + $dbop.PermissionType + " ON SCHEMA :: [" + $dbop.ObjectName + "] TO [" + $dbop.Grantee + "]"}
                default {$statement = $dbop.permissionState + " " + $dbop.PermissionType + " ON [" + $dbop.ObjectSchema + "].[" + $dbop.ObjectName + "] TO [" + $dbop.Grantee + "]"}
            }

            if ($PSCmdlet.ShouldProcess("$statement", "Setting permission"))
            {
                try {
                    $d.ExecuteWithResults($statement) | Out-Null
                    $Results.TotalSuccessful++
                    $Results.SuccessStatements += $statement
                } catch {
                    Write-Warning "Unable to apply '$statement'"
                    $Results.TotalError++
                    $Results.ErrorStatements += $statement
                }
            }
        }
    }
    $Results
}

