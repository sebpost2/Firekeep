# Add Server window (GUI replacement for Minecraft\scripts\new-server.ps1's
# Read-Host wizard). Launched in-process from Start-Gui.ps1's "New Server"
# entry. Runs creation on a background Job so the download/install (the
# slow part) doesn't freeze the window; a timer polls it and updates the
# status text, then the caller refreshes its server list on success.

param(
    [Parameter(Mandatory = $true)][string]$McRoot,
    [Parameter(Mandatory = $true)][string]$GsRoot,
    [System.Windows.Window]$Owner
)

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

[xml]$xamlXml = Get-Content -Path (Join-Path $GsRoot "_shared\gui\AddModpackWindow.xaml") -Raw
$window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xamlXml))
if ($Owner) { $window.Owner = $Owner }

$nameBox      = $window.FindName("NameBox")
$mrpackBox    = $window.FindName("MrpackBox")
$browseButton = $window.FindName("BrowseButton")
$ramBox       = $window.FindName("RamBox")
$eulaCheck    = $window.FindName("EulaCheck")
$hintText     = $window.FindName("HintText")
$createButton = $window.FindName("CreateButton")

$script:job = $null
$script:createdServerName = $null  # set on success, read by the caller after ShowDialog returns

$browseButton.Add_Click({
    $ofd = New-Object Microsoft.Win32.OpenFileDialog
    $ofd.Filter = "Modrinth modpack (*.mrpack)|*.mrpack"
    if ($ofd.ShowDialog() -eq $true) { $mrpackBox.Text = $ofd.FileName }
})

function Set-FormEnabled {
    param([bool]$Enabled)
    $nameBox.IsEnabled = $Enabled
    $mrpackBox.IsEnabled = $Enabled
    $browseButton.IsEnabled = $Enabled
    $ramBox.IsEnabled = $Enabled
    $eulaCheck.IsEnabled = $Enabled
    $createButton.IsEnabled = $Enabled
}

$createButton.Add_Click({
    $name = $nameBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($name)) { $hintText.Text = "Enter a server name."; return }
    if (-not $eulaCheck.IsChecked) { $hintText.Text = "You need to accept the Minecraft EULA to continue."; return }
    $mrpack = $mrpackBox.Text.Trim()
    $ram = $ramBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($ram)) { $ram = "6G" }

    Set-FormEnabled -Enabled $false
    $hintText.Text = "Creating '$name'..."

    $script:job = Start-Job -ScriptBlock {
        param($GsRoot, $McRoot, $Name, $MrpackPath, $MaxRam)
        . (Join-Path $GsRoot "_shared\scripts\new-server-helpers.ps1")
        $dest = New-ServerFromTemplate -Name $Name -McRoot $McRoot

        if ($MrpackPath) {
            . (Join-Path $GsRoot "_shared\scripts\mrpack-helpers.ps1")
            $mrpackExe = Join-Path $GsRoot "_shared\tools\mrpack.exe"
            $localMrpack = $MrpackPath
            if ($MrpackPath -match '^https?://') {
                $localMrpack = Join-Path $env:TEMP ("download-" + [Guid]::NewGuid().ToString("N") + ".mrpack")
                Invoke-WebRequest -Uri $MrpackPath -OutFile $localMrpack -UseBasicParsing
            } elseif (-not (Test-Path $MrpackPath)) {
                throw "Could not find the .mrpack file at '$MrpackPath'."
            }

            $mcVersion = Get-MinecraftVersionFromMrpack -MrpackPath $localMrpack
            $javaVersion = Get-JavaVersionForMinecraft -McVersion $mcVersion
            $loader = Get-ModpackLoader -MrpackPath $localMrpack
            if ($loader -ne "fabric") {
                Remove-Item -Recurse -Force $dest
                throw "This modpack uses $loader, which can't be installed automatically yet (Fabric only). Create the server without a modpack and copy the 'Server Files' in by hand (see README.md)."
            }

            & $mrpackExe $localMrpack --server-dir $dest
            if ($LASTEXITCODE -ne 0) {
                Remove-Item -Recurse -Force $dest
                throw "mrpack.exe failed installing the modpack (code $LASTEXITCODE)."
            }
            Set-RunConfigJavaAndRam -Path (Join-Path $dest "run.config.ps1") -JavaVersion $javaVersion -MaxRam $MaxRam
        }

        Set-Content -Path (Join-Path $dest "eula.txt") -Value "eula=true" -Encoding ascii
        return $Name
    } -ArgumentList $GsRoot, $McRoot, $name, $mrpack, $ram
})

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(500)
$timer.Add_Tick({
    if (-not $script:job -or $script:job.State -eq "Running" -or $script:job.State -eq "NotStarted") { return }

    if ($script:job.State -eq "Completed") {
        $script:createdServerName = Receive-Job $script:job
        $hintText.Text = "Done!"
        Remove-Job $script:job
        $script:job = $null
        $window.DialogResult = $true
        $window.Close()
        return
    }

    # Failed
    $reason = $script:job.ChildJobs[0].JobStateInfo.Reason.Message
    Remove-Job $script:job -Force
    $script:job = $null
    $hintText.Text = "Error: $reason"
    Set-FormEnabled -Enabled $true
})
$timer.Start()

$window.Add_Closing({
    if ($script:job) {
        Stop-Job $script:job -ErrorAction SilentlyContinue
        Remove-Job $script:job -Force -ErrorAction SilentlyContinue
    }
})

$window.ShowDialog() | Out-Null
$timer.Stop()

return $script:createdServerName
