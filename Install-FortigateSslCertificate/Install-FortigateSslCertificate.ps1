################################################################################
# Check https://github.com/thordreier/FortiGatePowerShellScripts
################################################################################
param(
	[Parameter(Position=0, Mandatory=$true)]
	[string]
	$CertCommonName,
	
	[Parameter(Position=1)]
	[string]
	$Firewall,
	
	[Parameter(Position=2)]
	[string]
	$DirPath = 'C:\Certificates',

	[Parameter()]
	[string]
	$CrtPath,

	[Parameter()]
	[string]
	$KeyPath,

	[Parameter()]
	[pscredential]
	$Credential,

	[Parameter()]
	[string]
	$Comment = 'Installed using PowerShell script'
)

$ErrorActionPreference = 'Stop'

function Invoke-SSHStreamCommandOrDie ($ShellStream, $Command, $ExpectRegex, $ErrorRegex = 'fail|error|unknown|invalid', $TimeOut = 2)
{
    $countdown = $Timeout * 10
    if ($Command) { $ShellStream.WriteLine($Command)}
    $all = ''
    do
    {
        --$countdown
        Start-Sleep -Milliseconds 100
        $all += $r = $ShellStream.Read()
        $r | Write-Host -NoNewline
        if ($ErrorRegex -and $all -match $ErrorRegex) {throw "Output mached '$ErrorRegex'"}
        if ($all -match $ExpectRegex) {return}
    }
    while ($countdown -gt 0)
    throw "Timeout: did not get correct output '$ExpectRegex' after $Timeout seconds"
}

if (-not $Firewall) { $Firewall = $CertCommonName }
$Firewall, $fwPort = $Firewall -split ':'
if (-not $CrtPath) { $CrtPath = Join-Path -Path $DirPath -ChildPath "$($CertCommonName)-chain.pem"}
if (-not $KeyPath) { $KeyPath = Join-Path -Path $DirPath -ChildPath "$($CertCommonName)-key.pem"}
if (-not $Credential) {$Credential = Get-VaultCredential -Name $Firewall}

$crtContent = (Get-Content -Raw -Path $crtPath) -replace '\r(\n)','$1'
$keyContent = (Get-Content -Raw -Path $keyPath) -replace '\r(\n)','$1'

$sshSessionParams = @{
    ComputerName = $Firewall
    Credential   = $Credential
}
if ($fwPort) {$sshSessionParams['Port'] = $fwPort}

$sshSession = New-SSHSession @sshSessionParams
$shellStream = New-SSHShellStream -SSHSession $sshSession

@(
    @{c=''                                ; e='\s#'}
    @{c='config vpn certificate local'    ; e='\(local\)\s#'}
    @{c="edit $CertCommonName"            ; e='\s#'}
    @{c="set comment `"$Comment`""        ; e='\s#'}
    @{c="set private-key `"$keyContent`"" ; e='\s#'}
    @{c="set certificate `"$crtContent`"" ; e='\s#'}
    @{c='next'                            ; e='\(local\)\s#'}
    @{c='end'                             ; e='\s#'}
    @{c='exit'                            ; e=''}
) | ForEach-Object -Process {
    Invoke-SSHStreamCommandOrDie -ShellStream $shellStream -Command $_.c -ExpectRegex $_.e
}
