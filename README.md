# AutomatedSQLPermissions

This repository contains two PowerShell functiosn designed to automate the process of capturing and re-applying database permissions.

#### Get-DatabasePermissions ####

This function is designed to scan a server and for each database pull out all the defined users, the roles they belong to, and each securable they have defined for database objects. The result of a scan will write the output to a database server (aka repository) where the script expects a series of tables to exist and it will write the output to them. 

#### Set-DatabasePermissions ####

This function is designed to connect to a repository database of stored user permissions and, finding any, will attempt to connect to a target server and re-apply them to the databases that it found permissions for.

## Usage Examples ##

Get all the permissions from every database on an instance and store them in a repository

Get all the permissions from a single database on an instance and store them in a repository

Reapply all the stored permissions in the repository from the most recent capture for a given instance

Reapply all the stored permissions in the repository from a given capture date for a given instance and specific database

## Repository Database Schema ##

Included in this repository is a .SQL script file that will create all the required database objects for use in this script.

## Helper Stored Procedure ##

Also included is a helper stored procedure that functions much like the "Get" function but can be run in T-SQL to manually return stored permission code.

## Requirements ##

You'll need a/the SQL Server PowerShell Module installed on the machine you want to run this on. Your repository database should be staged with the objects prior to runnning these functions.