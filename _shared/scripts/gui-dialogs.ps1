# Small reusable WPF dialogs shared by the Manage Maps and Add Modpack
# windows. Loaded via dot-source. Requires PresentationFramework already loaded.

# Text-entry prompt (WPF's MessageBox has no input box). Returns the entered
# text, or $null if cancelled/closed.
function Show-InputDialog {
    param(
        [Parameter(Mandatory = $true)][string]$GsRoot,
        [Parameter(Mandatory = $true)][string]$Prompt,
        [string]$DefaultValue = "",
        [System.Windows.Window]$Owner
    )
    [xml]$xamlXml = Get-Content -Path (Join-Path $GsRoot "_shared\gui\InputDialog.xaml") -Raw
    $dlg = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xamlXml))
    if ($Owner) { $dlg.Owner = $Owner }

    $promptText = $dlg.FindName("PromptText")
    $valueBox = $dlg.FindName("ValueBox")
    $okButton = $dlg.FindName("OkButton")
    $cancelButton = $dlg.FindName("CancelButton")

    $promptText.Text = $Prompt
    $valueBox.Text = $DefaultValue
    $valueBox.Focus() | Out-Null
    $valueBox.SelectAll()

    $okButton.Add_Click({ $dlg.DialogResult = $true })
    $cancelButton.Add_Click({ $dlg.DialogResult = $false })

    if ($dlg.ShowDialog()) { return $valueBox.Text }
    return $null
}

# Yes/No confirmation. Thin wrapper over MessageBox (native styling; not
# worth a custom window for a plain confirm/cancel).
function Show-ConfirmDialog {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [string]$Title = "Game Servers"
    )
    $result = [System.Windows.MessageBox]::Show($Message, $Title, "YesNo", "Warning")
    return $result -eq "Yes"
}
