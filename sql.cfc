<!---
	Name         : SQLCFC
	Version		 : 0.2
	Author       : Rob Gonda
	Created      : June 20, 2005
	Last Updated : November 30, 2005
	Purpose		 : SQL CFC
	History      : Alpha 0.1 working with SQL 2000 (rg 06.20.05)
				   tblUpdate will use the primary key value in the value structure if no update statement is passed (rg 11.30.05)
				   tblInsert was not inserting primary keys. Now it only ignores them if identity is present (rg 11.30.05)
				   added clearCache method (rg 12/2/05)
				   moved identity to its own column (rg 12/2/05)
				   added nullable column (rg 12/2/05)
				   added read_uncommitted tags for metadata queries (rg 12/2/05)
				   added setTrim method to modify the global trim behavior (rg 12/2/05)
				   updated getPrimaryKey to use information_schema (rg 12/4/05)
				   IMPORTANT: modified the order of the arguments in update/insert to leave all optional args together (rg 12/5/05)
				   
	notes		 : two ways of getting the meta data are
					EXEC sp_columns @table_name = 'table_name'
					SELECT * from INFORMATION_SCHEMA.COLUMNS where TABLE_NAME = 'table_name'	

--->
<cfcomponent displayname="SQLCFC">

	<!--- 
		function init
		initialized component with cache elements	
	 --->
	<cffunction name="init" access="public" output="No" returntype="sql" hint="Initializes the component">
		<cfargument name="datasource" required="Yes" type="string" />
		<cfargument name="username" required="Yes" type="string" />
		<cfargument name="password" required="Yes" type="string" />

		<cfscript>
			variables.instance = structNew();
			setDatasource(argumentcollection=arguments); // set datasource information
			clearCache(); // create cache struct
			
			variables.instance.trim = true;
			
			return this;
		</cfscript>
	</cffunction>

	<!--- 
		function setDatasource
		in:		
		out:	
		notes:	initializes the dataSource
	 --->
	<cffunction name="setDatasource" access="private" output="No" returntype="void" hint="Sets Datasource, user, and password">
		<cfargument name="datasource" required="Yes" type="string" />
		<cfargument name="username" required="Yes" type="string" />
		<cfargument name="password" required="Yes" type="string" />
		<cfscript>
			variables.dbsource = arguments.datasource;
			variables.dbuname = arguments.username;
			variables.dbpword = arguments.password;
		</cfscript>
	</cffunction>
	
	<!--- 
		function clearCache
		in:		
		out:	
		notes:	clears the cached metadata
	 --->
	<cffunction name="clearCache" access="public" output="No" returntype="void" hint="I clear the cache structure, or create one if null">
		<cfscript>
			variables.cache = structNew();
			variables.cache.tables = structNew();
		</cfscript>
	</cffunction>

	<!--- 
		function setTrim
		in:		
		out:	
		notes:	clears the cached metadata
	 --->
	<cffunction name="setTrim" access="public" output="No" returntype="void" hint="I turn on and off trimming">
		<cfargument name="trimBool" required="Yes" type="boolean" />
		<cfscript>
			variables.instance.trim = trimBool;
		</cfscript>
	</cffunction>

	<!--- 
		function getSQLSchema
		in:		table name
		out:	query with database schema
				contails all field name, lenghts, sql data types and cfsqltype
		notes:	runs SQL 2000 stored procedure to get SQL schema
				Attaches cfsqltypes equivalents to all fields
				caches the table in component
	 --->
	<cffunction name="getSQLSchema" access="public" returntype="query" output="No" hint="runs SQL 2000 stored procedure to get SQL schema">
		<cfargument name="tbl" required="Yes" type="string" />
		<cfset var qSchema = "" />
		<cfset var qPK = "" />
		<cfset var returnSchema = "" />
		
		<cfif StructKeyExists(variables.cache.tables,arguments.tbl)>
			<cfset returnSchema = variables.cache.tables[arguments.tbl] />
		<cfelse>
			<cftransaction isolation="read_uncommitted">
				<cfquery name="qSchema" datasource="#variables.dbsource#" username="#variables.dbuname#" password="#variables.dbpword#">
					EXEC sp_columns @table_name = '#arguments.tbl#'
				</cfquery>
			</cftransaction>
			<cfquery name="returnSchema" dbtype="query">
				select [COLUMN_NAME], [TYPE_NAME], [PRECISION], [NULLABLE] from qSchema
			</cfquery>
			<cfset qPK = getPrimaryKey(arguments.tbl) />
			<cfset QueryAddColumn(returnSchema,'CFSQLTYPE',arrayNew(1)) />
			<cfset QueryAddColumn(returnSchema,'PK',arrayNew(1)) />
			<cfset QueryAddColumn(returnSchema,'IDENTITY',arrayNew(1)) />
			<cfloop query="returnSchema">
				<cfset QuerySetCell(returnSchema,'CFSQLTYPE',SQL2cfsqltype(ListFirst(TYPE_NAME,' ')),currentrow) />
				<cfset QuerySetCell(returnSchema,'PK',iif(ListFindNoCase(ValueList(qPK.name),COLUMN_NAME),DE('1'),DE('0')),currentrow) />
				<cfset QuerySetCell(returnSchema,'IDENTITY',iif(ListLast(TYPE_NAME, ' ') eq 'identity',DE('1'),DE('0')),currentrow) />
				<cfset QuerySetCell(returnSchema,'TYPE_NAME',ListFirst(TYPE_NAME, ' '),currentrow) />
			</cfloop>
			<cfset variables.cache.tables[arguments.tbl] = returnSchema />
		</cfif>
		<cfreturn returnSchema />
	</cffunction>
	
	<!--- 
		function getPrimaryKey
		in:		table name
		out:	query with all primary keys for a table
		notes:	works only with SQL 2000 
				Checks for all primary keys in given table using the system tables
	 --->
	<cffunction name="getPrimaryKey" access="public" returntype="query" output="No" hint="Get all primary keys for a table">
		<cfargument name="tbl" required="Yes" type="string" />
		<cfset var qPK = "" />
			<cftransaction isolation="read_uncommitted">
				<cfquery name="qPK" datasource="#variables.dbsource#" username="#variables.dbuname#" password="#variables.dbpword#">
					SELECT 	C.COLUMN_NAME[name]
					FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS T
					     INNER JOIN INFORMATION_SCHEMA.CONSTRAINT_COLUMN_USAGE C
					     ON T.CONSTRAINT_NAME = C.CONSTRAINT_NAME
					WHERE T.CONSTRAINT_TYPE = 'PRIMARY KEY'
					      AND T.TABLE_NAME = '#arguments.tbl#'
				</cfquery>
			</cftransaction>
		<cfreturn qPK />
	</cffunction>
	
	
	<!--- 
		function getFieldType
			in:		table name
					field name
			out:	cfsqltype
	 --->
	<cffunction name="getFieldType" access="private" returntype="string" output="No" hint="Check table schema and returns cfsqltype">
		<cfargument name="tbl" required="Yes" type="string" />
		<cfargument name="fld" required="Yes" type="string" />
		<cfset var qReturn = "" />
		<cfset var tbl2 = "" />
		<cfif Not StructKeyExists(variables.cache.tables,arguments.tbl)>
			<cfthrow message="Table [#arguments.tbl#] not cached" />
		</cfif>
		<cfset tbl2 = variables.cache.tables[arguments.tbl]>
		<cfquery name="qReturn" dbtype="query">
			select CFSQLTYPE from tbl2 where COLUMN_NAME = '#fld#'
		</cfquery>
		<cfreturn qReturn.CFSQLTYPE />
	</cffunction>

	<!--- 
		function getFieldMaxLength
			in:		table name
					field name
			out:	MaxLength
	 --->
	<cffunction name="getFieldMaxLength" access="private" returntype="string" output="No" hint="Check table schema and returns MaxLength">
		<cfargument name="tbl" required="Yes" type="string" />
		<cfargument name="fld" required="Yes" type="string" />
		<cfset var q = "" />
		<cfset var t = "" />
		<cfif Not StructKeyExists(variables.cache.tables,arguments.tbl)>
			<cfthrow message="Table [#arguments.tbl#] not cached" />
		</cfif>
		<cfset t = variables.cache.tables[arguments.tbl] />
		<cfquery name="q" dbtype="query">
			select [PRECISION] from t where COLUMN_NAME = '#fld#'
		</cfquery>
		<cfreturn q.PRECISION />
	</cffunction>

	<!--- 
		function SQL2cfsqltype
		in:		SQL 2000 field type name
		out:	cfsqltype for given SQL data type
		notes:	called by getSQLSchema
	 --->
	<cffunction name="SQL2cfsqltype" access="private" returntype="string" output="No" hint="Transforms SQL Data Types into cfsqltype">
		<cfargument name="fieldType" required="Yes" type="string" />
		<cfset var r = "" />
		<cfswitch expression="#arguments.fieldType#">
			<cfcase value="bit"><cfset r = "CF_SQL_BIT"></cfcase>
			<cfcase value="char,nchar" delimiters=","><cfset r = "CF_SQL_CHAR"></cfcase>
			<cfcase value="binary" delimiters=","><cfset r = "CF_SQL_BINARY"></cfcase>
			<cfcase value="varbinary" delimiters=","><cfset r = "CF_SQL_VARBINARY"></cfcase>
			<cfcase value="text,ntext" delimiters=","><cfset r = "CF_SQL_LONGVARCHAR"></cfcase>
			<cfcase value="datetime,smalldatetime" delimiters=","><cfset r = "CF_SQL_TIMESTAMP"></cfcase>
			<cfcase value="float"><cfset r = "CF_SQL_FLOAT"></cfcase>
			<cfcase value="decimal"><cfset r = "CF_SQL_DECIMAL"></cfcase>
			<cfcase value="money,smallmoney" delimiters=","><cfset r = "CF_SQL_MONEY"></cfcase>
			<cfcase value="numeric"><cfset r = "CF_SQL_NUMERIC"></cfcase>
			<cfcase value="real"><cfset r = "CF_SQL_REAL"></cfcase>
			<cfcase value="int"><cfset r = "CF_SQL_INTEGER"></cfcase>
			<cfcase value="smallint"><cfset r = "CF_SQL_SMALLINT"></cfcase>
			<cfcase value="bigint"><cfset r = "CF_SQL_BIGINT"></cfcase>
			<cfcase value="tinyint"><cfset r = "CF_SQL_TINYINT"></cfcase>
			<cfcase value="timestamp"><cfset r = "CF_SQL_TIMESTAMP"></cfcase>
			<cfcase value="image"><cfset r = "CF_SQL_LONGVARBINARY"></cfcase>
			<cfcase value="varchar,nvarchar,uniqueidentifier"><cfset r = "CF_SQL_VARCHAR"></cfcase>
			<cfdefaultcase><cfset r = "ERROR"></cfdefaultcase>
		</cfswitch>
		<cfreturn r />
	</cffunction>

	
	<!--- 
		function tblUpdate
		in:		table name
				list of fields; if _auto is passed the component will cross check the table field list and the structure
					passed in vals and update all possible values
				structure with all fields values
				condition statement
				[trim] parameter to trim all values to maximum len
		out:	the number of rows updated
	 --->	
	<cffunction name="tblUpdate" returntype="numeric" access="public" output="No" hint="Update table">
		<cfargument name="tbl" required="Yes" type="string" />
		<cfargument name="vals" required="Yes" type="struct" />
		<cfargument name="flds" required="Yes" type="string" default="_auto" />
		<cfargument name="condition" required="Yes" type="string" default="" />
		<cfargument name="trim" required="No" type="boolean" default="#variables.instance.trim#" />

		<cfset var q = "" />
		<cfset var fldsArray = ListToArray(arguments.flds) />
		<cfset var qPK = "" />

		<!--- if field list is passed, check if all fields have values --->
		<cfloop from="1" to="#ArrayLen(fldsArray)#" index="i">
			<cfif fldsArray[i] neq "_auto" and Not StructKeyExists(arguments.vals,fldsArray[i])><cfthrow message="The value for [#fldsArray[i]#] was not passed"></cfif>
		</cfloop>
		
		<!--- If Schema is not cached, get schema --->
		<cfif Not StructKeyExists(variables.cache.tables,arguments.tbl)>
			<cfset getSQLSchema(arguments.tbl) />
		</cfif>
		
		<!--- if _auto, determine which fields need to be updated --->
		<cfif fldsArray[1] eq "_auto">
			<cfset fldsArray = ArrayNew(1) />
			<cfset q = variables.cache.tables[arguments.tbl] />
			<cfloop query="q">
				<cfif PK neq 1 and IDENTITY neq 1> <!--- ignore identities and primery keys --->
					<cfif StructKeyExists(vals,COLUMN_NAME)> <!--- if sql field name exists in vals structure --->
						<cfset ArrayAppend(fldsArray,COLUMN_NAME) />
					</cfif>
				</cfif>
			</cfloop>
		</cfif>
		
		<cfif arrayLen(fldsArray) eq 0>
			<cfthrow message="Cannot update [#arguments.tbl#] because no fields matched the database schema" />
		</cfif>
		
		<!--- if condition is not passed --->
		<cfif not len(arguments.condition)>
			<cfset qPK = getPrimaryKey(arguments.tbl)>
			<cfloop query="qPK">
				<cfif structKeyExists(arguments.vals, qPK.name)> <!--- primary key was passed with the values --->
					<cfset arguments.condition = ListAppend(arguments.condition, '#qPK.name#=''#arguments.vals[qPK.name]#''', chr(7)) /> <!--- note: use special character for delimited, to be replace later by multi-character delimited --->
				<cfelse>
					<cfthrow message="Cannot update [#arguments.tbl#] because condition or primary key were not passed" />
				</cfif>
			</cfloop>
			<cfset arguments.condition = replace(arguments.condition, chr(7), ' AND ', 'ALL' ) /> <!--- replace special character by AND operator --->
		</cfif>

		<cfquery name="q" datasource="#variables.dbsource#" username="#variables.dbuname#" password="#variables.dbpword#">
			update #arguments.tbl# set 
				<cfloop from="1" to="#ArrayLen(fldsArray)#" index="i">
					#fldsArray[i]# = <cfqueryparam 
										cfsqltype="#getFieldType(arguments.tbl,fldsArray[i])#" 
										value="#iif(arguments.trim,'LEFT(arguments.vals[fldsArray[i]],getFieldMaxLength(arguments.tbl,fldsArray[i]))','arguments.vals[fldsArray[i]]')#" 
										maxlength="#getFieldMaxLength(arguments.tbl,fldsArray[i])#"
										null="#iif(LEN(arguments.vals[fldsArray[i]]),DE('NO'),DE('YES'))#"><cfif i neq ArrayLen(fldsArray)>,</cfif>
				</cfloop>
			where #PreserveSingleQuotes(arguments.condition)#;
			SELECT @@ROWCOUNT as c
		</cfquery>
		<cfreturn q.c />
	</cffunction>
	
	<!--- 
		function tblInsert
		in:		table name
				list of fields; if _auto is passed the component will cross check the table field list and the structure
					passed in vals and update all possible values
				structure with all fields values
				[trim] parameter to trim all values to maximum len
		out:	Primary Key
	 --->	
	<cffunction name="tblInsert" returntype="string" access="public" output="No" hint="Insert into table">
		<cfargument name="tbl" required="Yes" type="string" />
		<cfargument name="vals" required="Yes" type="struct" />
		<cfargument name="flds" required="Yes" type="string" default="_auto" />
		<cfargument name="trim" required="No" type="boolean" default="#variables.instance.trim#" />
		
		<cfset var q = "" />
		<cfset var fldsArray = ListToArray(arguments.flds) />
		
		<!--- check if all fields have values --->
		<cfloop from="1" to="#ArrayLen(fldsArray)#" index="i">
			<cfif fldsArray[i] neq "_auto" and Not StructKeyExists(arguments.vals,fldsArray[i])><cfthrow message="The value for [#fldsArray[i]#] was not passed"></cfif>
		</cfloop>
		
		<!--- If Schema is not cached, get schema --->
		<cfif Not StructKeyExists(variables.cache.tables,arguments.tbl)>
			<cfset getSQLSchema(arguments.tbl) />
		</cfif>

		<cfif fldsArray[1] eq "_auto">
			<cfset fldsArray = ArrayNew(1) />
			<cfset q = variables.cache.tables[arguments.tbl] />
			<cfloop query="q">
				<cfif IDENTITY neq 1> <!--- ignore identities --->
					<cfif StructKeyExists(vals,COLUMN_NAME)> <!--- if sql field name exists in vals structure --->
						<cfset ArrayAppend(fldsArray,COLUMN_NAME) />
					</cfif>
				</cfif>
			</cfloop>
		</cfif>

		<cfquery name="q" datasource="#variables.dbsource#" username="#variables.dbuname#" password="#variables.dbpword#">
			insert into #arguments.tbl# (#ArrayToList(fldsArray)#)
			values (<cfloop from="1" to="#ArrayLen(fldsArray)#" index="i">
					<cfqueryparam 
						cfsqltype="#getFieldType(arguments.tbl,fldsArray[i])#" 
						value="#iif(arguments.trim,'LEFT(arguments.vals[fldsArray[i]],getFieldMaxLength(arguments.tbl,fldsArray[i]))','arguments.vals[fldsArray[i]]')#" 
						maxlength="#getFieldMaxLength(arguments.tbl,fldsArray[i])#"
						null="#iif(LEN(arguments.vals[fldsArray[i]]),DE('NO'),DE('YES'))#"><cfif i neq ArrayLen(fldsArray)>,</cfif>
				</cfloop>)
			SELECT @@identity as uid 
		</cfquery>
		<cfreturn q.uid />
	</cffunction>

	<!--- 
		function tblDelete
		in:		table name
				condition statement
		out:	the number of rows deleted
	 --->	
	<cffunction name="tblDelete" returntype="numeric" access="public" output="No" hint="Delete from Table">
		<cfargument name="tbl" required="Yes" type="string" />
		<cfargument name="condition" required="Yes" type="string" default="" />

		<cfset var q = "" />
		<cfset var qPK = "" />

		<!--- if condition is not passed --->
		<cfif not len(arguments.condition)>
			<cfset qPK = getPrimaryKey(arguments.tbl) />
			<cfloop query="qPK">
				<cfif structKeyExists(arguments.vals, qPK.name)> <!--- primary key was passed with the values --->
					<cfset arguments.condition = ListAppend(arguments.condition, '#qPK.name#=''#arguments.vals[qPK.name]#''', chr(7)) />
				<cfelse>
					<cfthrow message="Cannot delete from [#arguments.tbl#] condition or because primary key were not passed" />
				</cfif>
			</cfloop>
			<cfset arguments.condition = replace(arguments.condition, chr(7), ' AND ', 'ALL' ) />
		</cfif>

		
		<cfquery name="q" datasource="#variables.dbsource#" username="#variables.dbuname#" password="#variables.dbpword#">
			delete from #arguments.tbl#
			where #PreserveSingleQuotes(arguments.condition)#
			SELECT @@ROWCOUNT as c
		</cfquery>
		<cfreturn q.c />
	</cffunction>

	<!--- 
		function tblSelect
		in:		table name
				fields
				condition statement
		out:	recordset
	 --->	
	<cffunction name="tblSelect" returntype="query" access="public" output="No" hint="Select from Table">
		<cfargument name="tbl" required="Yes" type="string" />
		<cfargument name="flds" required="Yes" type="string" default="*" />
		<cfargument name="condition" required="No" type="string" default="" />
		<cfargument name="sortby" required="No" type="string" default="" />
		<cfargument name="groupby" required="No" type="string" default="" />
		<cfset var q = "" />
		
		<cfquery name="q" datasource="#variables.dbsource#" username="#variables.dbuname#" password="#variables.dbpword#">
			select #arguments.flds# from #arguments.tbl#
			<cfif len(arguments.condition)>where #PreserveSingleQuotes(arguments.condition)#</cfif>
			<cfif len(arguments.groupby)>group by #PreserveSingleQuotes(arguments.groupby)#</cfif>
			<cfif len(arguments.sortby)>order by #PreserveSingleQuotes(arguments.sortby)#</cfif>
		</cfquery>
		<cfreturn q />
	</cffunction>
</cfcomponent>

