CREATE SCHEMA [Permissions]
GO


SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [Permissions].[Captures](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[CaptureID] [uniqueidentifier] NOT NULL,
	[CaptureDateTime] [datetime2](7) NOT NULL,
	[ServerName] [nvarchar](50) NOT NULL,
	[InstanceName] [nvarchar](50) NOT NULL,
	[DatabaseName] [nvarchar](150) NOT NULL,
PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
) ON [PRIMARY]
GO

/****** Object:  Table [Permissions].[DatabaseObjectPermissions]    Script Date: 2/2/2018 3:26:05 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [Permissions].[DatabaseObjectPermissions](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[CaptureID] [uniqueidentifier] NOT NULL,
	[ObjectClass] [nvarchar](150) NULL,
	[ObjectSchema] [nvarchar](150) NULL,
	[ObjectName] [nvarchar](150) NOT NULL,
	[PermissionState] [nvarchar](50) NOT NULL,
	[PermissionType] [nvarchar](50) NOT NULL,
	[Grantee] [nvarchar](150) NOT NULL,
	[CreateScript] [nvarchar](max) NULL,
PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO

/****** Object:  Table [Permissions].[DatabaseRoleMembers]    Script Date: 2/2/2018 3:26:05 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [Permissions].[DatabaseRoleMembers](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[CaptureID] [uniqueidentifier] NOT NULL,
	[RoleName] [nvarchar](100) NOT NULL,
	[RoleMember] [nvarchar](100) NOT NULL,
	[CreateScript] [nvarchar](max) NULL,
PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO

/****** Object:  Table [Permissions].[DatabaseUsers]    Script Date: 2/2/2018 3:26:05 PM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [Permissions].[DatabaseUsers](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[CaptureID] [uniqueidentifier] NOT NULL,
	[UserName] [nvarchar](100) NOT NULL,
	[CreateScript] [nvarchar](max) NULL,
PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON, FILLFACTOR = 80) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]
GO



CREATE PROCEDURE [Permissions].[GetPermissions]
	@ForServer nvarchar(255),
	@ForDatabase nvarchar(255),
	@ForDate date
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @WorkingDate DATE

	SELECT TOP (1000) [ID]
		  ,[CaptureID]
		  ,[CaptureDateTime]
		  ,[ServerName]
		  ,[InstanceName]
		  ,[DatabaseName]
	INTO #AllCaptures
	FROM [Admin].[Permissions].[Captures]
	where servername = @ForServer
	order by capturedatetime desc

	IF @ForDate IS NULL
	BEGIN 
  		select top 1  @ForDate = CaptureDateTime from #AllCaptures where servername = 'int-excelsql-02\con3'
		group by capturedatetime
		order by CaptureDateTime DESC
	END

	DELETE FROM #AllCaptures WHERE CAST(CaptureDateTime AS DATE) <> @ForDate

	IF @ForDatabase IS NULL
	BEGIN
		DELETE FROM #AllCaptures WHERE DatabaseName <> @ForDatabase
	END

	SELECT c.CaptureDateTime, c.ServerName, c.InstanceName, c.DatabaseName, 'USE [' + c.DatabaseName + ']; ' + CreateScript
    FROM Permissions.DatabaseUsers u
	INNER JOIN Permissions.Captures c ON  c.CaptureID = u.CaptureID
	INNER JOIN #AllCaptures ac ON ac.CaptureID = c.CaptureID

	 UNION ALL

	 SELECT 
		c.CaptureDateTime, c.ServerName, c.InstanceName, c.DatabaseName, 'USE [' + c.DatabaseName + ']; ' + 'ALTER ROLE ' + r.RoleName + ' ADD MEMBER [' + r.RoleMember + ']' 
	 FROM Permissions.DatabaseRoleMembers r
	 INNER JOIN Permissions.Captures c ON c.CaptureID = r.CaptureID
	 INNER JOIN #AllCaptures ac ON ac.CaptureID = c.CaptureID

	 UNION ALL

	 SELECT 
		c.CaptureDateTime, c.ServerName, c.InstanceName, c.DatabaseName, 'USE [' + c.DatabaseName + ']; ' + (p.PermissionState + ' ' + p.PermissionType + ' TO [' + p.Grantee + ']')
	 FROM Permissions.DatabaseObjectPermissions p
	 INNER JOIN Permissions.Captures c ON c.CaptureID = p.CaptureID
	 INNER JOIN #AllCaptures ac ON ac.CaptureID = c.CaptureID
	 AND ObjectClass = 'Database' 

	 UNION ALL

	SELECT 
		c.CaptureDateTime, c.ServerName, c.InstanceName, c.DatabaseName, 
		Code = 
	CASE 
		WHEN ObjectClass = 'Schema' THEN 'USE [' + c.DatabaseName + ']; ' + ' ' + permissionState + ' ' + permissionType + ' ON SCHEMA:: [' + ObjectName + '] TO [' + Grantee + ']'
		ELSE 'USE [' + c.DatabaseName + ']; ' + permissionState + ' ' + permissionType +  ' ON [' + objectSchema + '].[' + objectname + '] TO [' + grantee + ']'
	END
	FROM Permissions.DatabaseObjectPermissions p
	INNER JOIN Permissions.Captures c ON c.CaptureID = p.CaptureID
	INNER JOIN #AllCaptures ac ON ac.CaptureID = c.CaptureID
	AND ObjectClass != 'Database' 

END
GO


