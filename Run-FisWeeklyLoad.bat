@echo off
setlocal
title FIS Weekly S3 to Snowflake Loader
set "FIS_LOADER_SELF=%~f0"
set "FIS_LOADER_LOG=%~dp0FisWeeklyLoad-last.log"
if exist "%FIS_LOADER_LOG%" del /q "%FIS_LOADER_LOG%"
powershell.exe -NoLogo -NoProfile -Command "$raw=[IO.File]::ReadAllText($env:FIS_LOADER_SELF); $marker=':FIS_POWERSHELL_PAYLOAD'; $start=$raw.LastIndexOf($marker); if($start -lt 0){Write-Error 'Embedded loader payload is missing.'; exit 1}; $code=$raw.Substring($start+$marker.Length); try { & ([ScriptBlock]::Create($code)) *>&1 | Tee-Object -FilePath $env:FIS_LOADER_LOG; if(-not $?){exit 1} } catch { $_ | Out-String | Tee-Object -FilePath $env:FIS_LOADER_LOG -Append | Write-Host; exit 1 }"
set "FIS_LOADER_EXIT=%ERRORLEVEL%"
echo.
if "%FIS_LOADER_EXIT%"=="0" (echo [SUCCESS] Loader completed.) else (echo [ERROR] Loader stopped with exit code %FIS_LOADER_EXIT%.)
echo Full log: "%FIS_LOADER_LOG%"
echo.
:FIS_KEEP_OPEN
set "FIS_CLOSE="
set /p "FIS_CLOSE=Type EXIT and press Enter to close this window: "
if /i not "%FIS_CLOSE%"=="EXIT" goto FIS_KEEP_OPEN
exit /b %FIS_LOADER_EXIT%
:FIS_POWERSHELL_PAYLOAD
[CmdletBinding()]
param(
    [switch] $KeepDownloadedFile,
    [switch] $KeepStagedFile
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$Bucket = "actimize-acthos-prod-euw1"
$Prefix = "FIS/SCHEDULED_REPORTS/"
$FileNameContains = "FIS_Sanctions_Alert_Weekly_"
$AwsRegion = "eu-west-1"

$SnowConnection = "cdp_prd"
$SnowRole = "USER_RL_E6004592"
$SnowWarehouse = "COMPLIANCE_SCREENING_SANDBOX__M__WH"
$SnowDatabase = "COMPLIANCE_SCREENING_SANDBOX"
$SnowSchema = "RAW"
$SnowTable = "FIS_SCHEDULED_REPORTS_RAW"
$SnowStage = "COMPLIANCE_SCREENING_SANDBOX.INTERNAL_STAGE.ALERT_STAGE"
$SnowFileFormat = "COMPLIANCE_SCREENING_SANDBOX.RAW.FIS_SCHEDULED_REPORTS_PIPE_FORMAT"

$SourceColumns = @(
    "ALERT_ID", "ALERT_DATE", "ENTITY_IDENTIFIER", "ENTITY_TYPE_ID", "JOB_ID",
    "PARTY_KEY", "CUSTOMER_TYPE", "MATCH_TYPE", "JOB_NAME",
    "SEARCH_CONFIGURATION_NAME", "PARTY_FULL_NAME", "IDS", "LIST_ENTRY_IDS",
    "CATEGORIES_HIT_ON", "HIT_DOB", "JOB_TYPE",
    "PREVIOUS_ELIGIBILITY_STATUS", "KEYWORDS_HIT_ON", "PARENT_ID",
    "HITS_HIGHLIGHTS", "WATCH_LISTS", "SCORE", "RFI_DEADLINE",
    "EMAIL_ADDRESS", "SOURCE_SYSTEM_IDENTIFIER", "REMARK",
    "DOING_BUSINESS_AS", "PARTY_TYPE", "HIT_NAME", "HIT_IDS",
    "NUMBER_OF_HITS", "DATE_OF_BIRTH_FORMATION", "BUSINESS_UNIT", "ISSUE",
    "STEP", "ALERT_RFI_STATE", "OWNER_FULL_NAME", "OWNER_LOGIN_NAME",
    "OWNER_EXTERNAL_IDENTIFIER", "LAST_UPDATE_USER", "ALERT_TYPE_NAME",
    "ALERT_TYPE_SHORT_NAME", "CLOSED_DATE", "CREATE_DATE", "LAST_UPDATE_DATE"
)

function Write-Step {
    param([string] $Text)
    Write-Host ""
    Write-Host ("==> " + $Text) -ForegroundColor Cyan
}

function Write-Success {
    param([string] $Text)
    Write-Host ("[OK] " + $Text) -ForegroundColor Green
}

function Invoke-Native {
    param(
        [string] $Program,
        [string[]] $Arguments,
        [string] $FailureMessage
    )
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$FailureMessage (exit code $LASTEXITCODE)."
    }
}

function Invoke-SnowSql {
    param(
        [string] $Query,
        [string] $Description
    )
    Write-Step $Description
    Invoke-Native -Program "snow" `
        -Arguments @("sql", "-c", $SnowConnection, "-q", $Query) `
        -FailureMessage $Description
}

function Read-SecretText {
    param([string] $Prompt)
    $secureValue = Read-Host -Prompt $Prompt -AsSecureString
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureValue)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
}

foreach ($command in @("aws", "snow")) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "'$command' was not found in PATH."
    }
}

$CredentialsPrompted = $false
if (-not $env:AWS_ACCESS_KEY_ID -or -not $env:AWS_SECRET_ACCESS_KEY) {
    Write-Host ""
    Write-Host "AWS credentials are required for this run." -ForegroundColor Yellow
    Write-Host "Input is hidden and is not saved to disk." -ForegroundColor DarkGray
    $env:AWS_ACCESS_KEY_ID = Read-SecretText -Prompt "AWS access key ID"
    $env:AWS_SECRET_ACCESS_KEY = Read-SecretText -Prompt "AWS secret access key"
    $env:AWS_SESSION_TOKEN = $null
    $CredentialsPrompted = $true
}

$RunId = [guid]::NewGuid().ToString("N")
$WorkDirectory = Join-Path $env:TEMP "fis-weekly-load-$RunId"
$LocalFile = $null
$StagePath = $null
$Uploaded = $false

$SessionSql = @"
USE ROLE $SnowRole;
USE WAREHOUSE $SnowWarehouse;
USE DATABASE $SnowDatabase;
USE SCHEMA $SnowSchema;
"@

$CreateObjectsSql = @"
$SessionSql
CREATE FILE FORMAT IF NOT EXISTS $SnowFileFormat
  TYPE = CSV
  FIELD_DELIMITER = '|'
  SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  TRIM_SPACE = TRUE
  NULL_IF = ('', 'NULL', 'null')
  EMPTY_FIELD_AS_NULL = TRUE
  ERROR_ON_COLUMN_COUNT_MISMATCH = TRUE
  MULTI_LINE = TRUE
  ENCODING = 'UTF8';

CREATE TABLE IF NOT EXISTS $SnowDatabase.$SnowSchema.$SnowTable (
  ALERT_ID VARCHAR,
  ALERT_DATE VARCHAR,
  ENTITY_IDENTIFIER VARCHAR,
  ENTITY_TYPE_ID VARCHAR,
  JOB_ID VARCHAR,
  PARTY_KEY VARCHAR,
  CUSTOMER_TYPE VARCHAR,
  MATCH_TYPE VARCHAR,
  JOB_NAME VARCHAR,
  SEARCH_CONFIGURATION_NAME VARCHAR,
  PARTY_FULL_NAME VARCHAR,
  IDS VARCHAR,
  LIST_ENTRY_IDS VARCHAR,
  CATEGORIES_HIT_ON VARCHAR,
  HIT_DOB VARCHAR,
  JOB_TYPE VARCHAR,
  PREVIOUS_ELIGIBILITY_STATUS VARCHAR,
  KEYWORDS_HIT_ON VARCHAR,
  PARENT_ID VARCHAR,
  HITS_HIGHLIGHTS VARCHAR,
  WATCH_LISTS VARCHAR,
  SCORE VARCHAR,
  RFI_DEADLINE VARCHAR,
  EMAIL_ADDRESS VARCHAR,
  SOURCE_SYSTEM_IDENTIFIER VARCHAR,
  REMARK VARCHAR,
  DOING_BUSINESS_AS VARCHAR,
  PARTY_TYPE VARCHAR,
  HIT_NAME VARCHAR,
  HIT_IDS VARCHAR,
  NUMBER_OF_HITS VARCHAR,
  DATE_OF_BIRTH_FORMATION VARCHAR,
  BUSINESS_UNIT VARCHAR,
  ISSUE VARCHAR,
  STEP VARCHAR,
  ALERT_RFI_STATE VARCHAR,
  OWNER_FULL_NAME VARCHAR,
  OWNER_LOGIN_NAME VARCHAR,
  OWNER_EXTERNAL_IDENTIFIER VARCHAR,
  LAST_UPDATE_USER VARCHAR,
  ALERT_TYPE_NAME VARCHAR,
  ALERT_TYPE_SHORT_NAME VARCHAR,
  CLOSED_DATE VARCHAR,
  CREATE_DATE VARCHAR,
  LAST_UPDATE_DATE VARCHAR,
  INGESTED_AT TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
);
"@

try {
    New-Item -ItemType Directory -Path $WorkDirectory -Force | Out-Null

    Write-Step "Verify active AWS identity"
    Invoke-Native -Program "aws" `
        -Arguments @("sts", "get-caller-identity", "--region", $AwsRegion, "--output", "table") `
        -FailureMessage "AWS authentication check failed"
    Write-Success "AWS connection established"

    Write-Step "Find newest matching S3 object"
    $LatestQuery = "reverse(sort_by(Contents[?Size > ``0`` && contains(Key, '$FileNameContains')], &LastModified))[0].Key"
    $LatestKey = & aws s3api list-objects-v2 `
        --bucket $Bucket `
        --prefix $Prefix `
        --region $AwsRegion `
        --query $LatestQuery `
        --output text
    if ($LASTEXITCODE -ne 0) {
        throw "S3 object listing failed."
    }
    $LatestKey = ([string]$LatestKey).Trim()
    if ([string]::IsNullOrWhiteSpace($LatestKey) -or $LatestKey -eq "None") {
        throw "No non-empty object containing '$FileNameContains' was found under s3://$Bucket/$Prefix."
    }
    $LatestS3Uri = "s3://$Bucket/$LatestKey"
    $FileName = Split-Path -Leaf $LatestKey
    $LocalFile = Join-Path $WorkDirectory $FileName
    Write-Host ("Latest file: " + $LatestS3Uri) -ForegroundColor Yellow

    Write-Step "Download latest CSV"
    Invoke-Native -Program "aws" `
        -Arguments @("s3", "cp", $LatestS3Uri, $LocalFile, "--region", $AwsRegion, "--only-show-errors") `
        -FailureMessage "S3 download failed"
    $Downloaded = Get-Item -LiteralPath $LocalFile
    Write-Success ("Downloaded {0:N0} bytes to {1}" -f $Downloaded.Length, $Downloaded.FullName)

    Write-Step "Verify approved Snowflake CLI connection"
    Invoke-Native -Program "snow" `
        -Arguments @("connection", "test", "-c", $SnowConnection) `
        -FailureMessage "Snowflake connection test failed"
    Write-Success "Snowflake connection established"

    Invoke-SnowSql -Query $CreateObjectsSql -Description "Ensure pipe file format and RAW table exist"

    $StageFolder = "fis_weekly_load/$RunId"
    $StagePath = "@$SnowStage/$StageFolder"
    $SnowLocalPath = $LocalFile.Replace("\", "/").Replace("'", "''")
    $PutSql = @"
$SessionSql
PUT 'file://$SnowLocalPath' $StagePath
  AUTO_COMPRESS = TRUE
  OVERWRITE = TRUE;
LIST $StagePath;
"@
    Invoke-SnowSql -Query $PutSql -Description "Upload downloaded CSV to the approved internal stage"
    $Uploaded = $true

    $StageCountSql = @"
$SessionSql
SELECT COUNT(*) AS STAGED_DATA_ROWS
FROM $StagePath (FILE_FORMAT => '$SnowFileFormat');
"@
    Invoke-SnowSql -Query $StageCountSql -Description "Count parsed data rows before loading"

    $ColumnList = $SourceColumns -join ", "
    $CopySql = @"
$SessionSql
COPY INTO $SnowDatabase.$SnowSchema.$SnowTable ($ColumnList)
FROM $StagePath
FILE_FORMAT = (FORMAT_NAME = '$SnowFileFormat')
ON_ERROR = 'ABORT_STATEMENT';

SELECT COUNT(*) AS TOTAL_TABLE_ROWS
FROM $SnowDatabase.$SnowSchema.$SnowTable;

SELECT *
FROM $SnowDatabase.$SnowSchema.$SnowTable
ORDER BY INGESTED_AT DESC
LIMIT 10;
"@
    Invoke-SnowSql -Query $CopySql -Description "Load RAW table and display row count plus sample"
    Write-Success "End-to-end load completed"
}
finally {
    if ($Uploaded -and -not $KeepStagedFile) {
        $RemoveSql = "$SessionSql`nREMOVE $StagePath;"
        Write-Step "Remove this run's staged file"
        & snow sql -c $SnowConnection -q $RemoveSql | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "The load finished, but staged-file cleanup failed: $StagePath"
        }
    }

    if ($null -ne $LocalFile -and (Test-Path -LiteralPath $LocalFile)) {
        if ($KeepDownloadedFile) {
            Write-Host ("Downloaded file retained at: " + $LocalFile) -ForegroundColor Yellow
        }
        else {
            Remove-Item -LiteralPath $LocalFile -Force
        }
    }
    if (Test-Path -LiteralPath $WorkDirectory) {
        $remainingItems = @(Get-ChildItem -LiteralPath $WorkDirectory -Force)
        if ($remainingItems.Count -eq 0) {
            Remove-Item -LiteralPath $WorkDirectory -Force
        }
    }
    if ($CredentialsPrompted) {
        $env:AWS_ACCESS_KEY_ID = $null
        $env:AWS_SECRET_ACCESS_KEY = $null
        $env:AWS_SESSION_TOKEN = $null
    }
}
