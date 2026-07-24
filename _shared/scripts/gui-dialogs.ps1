# Small reusable prompts shown as an in-window overlay (PromptOverlay.xaml)
# instead of a separate popup window - the whole app is one Window now, this
# just dims it and shows a small card on top. Loaded via dot-source.
#
# WPF has no synchronous way to "wait" for an overlay click the way
# ShowDialog() waits for a window, so these use the standard trick for that:
# push a nested Dispatcher frame that keeps processing UI events (clicks,
# repaints) until the Ok/Cancel handler ends it, then return like a normal
# blocking call. $Overlay is the object built once in Start-Gui.ps1:
# @{ Host = <ContentControl>; PromptText/ValueBox/OkButton/CancelButton = <elements> }

# Text-entry prompt. Returns the entered text, or $null if cancelled/closed.
function Show-InputDialog {
    param(
        [Parameter(Mandatory = $true)]$Overlay,
        [Parameter(Mandatory = $true)][string]$Prompt,
        [string]$DefaultValue = ""
    )
    $Overlay.ValueBox.Visibility = "Visible"
    $Overlay.PromptText.Text = $Prompt
    $Overlay.ValueBox.Text = $DefaultValue
    $Overlay.OkButton.Content = "OK"
    $Overlay.CancelButton.Content = "Cancel"
    $Overlay.Host.Visibility = "Visible"
    $Overlay.ValueBox.Focus() | Out-Null
    $Overlay.ValueBox.SelectAll()

    $result = Wait-OverlayResult -Overlay $Overlay

    $Overlay.Host.Visibility = "Collapsed"
    if ($result) { return $Overlay.ValueBox.Text }
    return $null
}

# Yes/No confirmation, same overlay card with the text box hidden.
function Show-ConfirmDialog {
    param(
        [Parameter(Mandatory = $true)]$Overlay,
        [Parameter(Mandatory = $true)][string]$Message
    )
    $Overlay.ValueBox.Visibility = "Collapsed"
    $Overlay.PromptText.Text = $Message
    $Overlay.OkButton.Content = "Yes"
    $Overlay.CancelButton.Content = "No"
    $Overlay.Host.Visibility = "Visible"
    $Overlay.OkButton.Focus() | Out-Null

    $result = Wait-OverlayResult -Overlay $Overlay

    $Overlay.Host.Visibility = "Collapsed"
    $Overlay.ValueBox.Visibility = "Visible"
    return [bool]$result
}

# Blocks (without freezing the UI) until Ok or Cancel is clicked on the
# overlay currently showing, via a nested Dispatcher frame.
function Wait-OverlayResult {
    param([Parameter(Mandatory = $true)]$Overlay)

    $script:overlayResult = $null
    $frame = New-Object System.Windows.Threading.DispatcherFrame

    $okHandler = { $script:overlayResult = $true; $frame.Continue = $false }
    $cancelHandler = { $script:overlayResult = $false; $frame.Continue = $false }
    $Overlay.OkButton.Add_Click($okHandler)
    $Overlay.CancelButton.Add_Click($cancelHandler)

    [System.Windows.Threading.Dispatcher]::PushFrame($frame)

    $Overlay.OkButton.Remove_Click($okHandler)
    $Overlay.CancelButton.Remove_Click($cancelHandler)

    return $script:overlayResult
}
