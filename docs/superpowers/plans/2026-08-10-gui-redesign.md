# GUI Redesign (Verity panel + whole-app polish) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the cramped, overlapping Local AI (Verity) panel and give the whole client-facing WPF launcher a more polished, breathable "refined campfire" look, by making the window resizable and consolidating the 6 XAML files' duplicated resources into one shared theme.

**Architecture:** The app is loose XAML loaded at runtime by `Start-Gui.ps1` via `XamlReader.Load` (no compiled `App.xaml`, no `pack://` merged dictionaries available). A new `_shared/gui/Theme.xaml` (a bare `<ResourceDictionary>`) is loaded once and merged programmatically into every screen root's `Resources.MergedDictionaries` in `Start-Gui.ps1`. Each screen's `<Grid.Resources>` duplication is deleted. The Verity panel's 3 status rows become 3 sidecar cards (chosen design: Option B from brainstorming). The window becomes resizable with bumped per-screen sizes.

**Tech Stack:** PowerShell 5.1+ WPF (`PresentationFramework`), loose XAML, Pester (tests use `Should Be`, old Pester v3/v4 syntax — match `tests/gui-helpers.tests.ps1`).

## Global Constraints

- Keep the existing campfire palette (colors unchanged) — only spacing, type scale, layout, and the Verity panel structure change.
- Preserve every existing `x:Name` that `Start-Gui.ps1` calls `FindName` on, unless a step explicitly says to rename it (and updates the matching `FindName` call in the same step).
- Follow the codebase's existing test convention: pure logic lives in `_shared/scripts/gui-helpers.ps1` and is Pester-tested; XAML structure and event-wiring in `Start-Gui.ps1` are verified by manually launching the app (see `_shared/scripts/gui-helpers.ps1:1-3`). Don't invent new test infrastructure beyond this.
- Pester syntax in this repo is old-style: `$x | Should Be $y` (not `Should -Be`).

---

### Task 1: Create the shared theme file

**Files:**
- Create: `_shared/gui/Theme.xaml`

**Interfaces:**
- Produces: a `ResourceDictionary` (root element, no `Grid`) containing every brush and style key currently duplicated across `HomeScreen.xaml`, `ConsoleScreen.xaml`, `AddServerScreen.xaml`, `ManageMapsScreen.xaml`, `PromptOverlay.xaml`. Later tasks merge this into each screen's resources and delete the screens' own `<Grid.Resources>` blocks.
- Two resources are intentionally unified where the 5 files previously disagreed:
  - `ActionButtonStyle`: standardized on `FontSize="16"`, `Padding="0,14"` (was 16/0,14 on Home, 15/0,12 on Add Server — Add Server now matches Home).
  - `LinkButtonStyle`: standardized on hover `Foreground="{StaticResource AccentBrush}"` (was `TextBrush` on Home's copy, `AccentBrush` on Add Server's copy — Home now matches Add Server).
  - `BackButtonStyle`: standardized on the Add Server version, which included an `IsEnabled` trigger (`Opacity 0.4`) that Console's and Manage Maps' copies lacked. Purely defensive; the back button is always enabled today so this changes nothing visible yet.

- [ ] **Step 1: Write `_shared/gui/Theme.xaml`**

```xml
<ResourceDictionary
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">

    <SolidColorBrush x:Key="PanelBrush" Color="#262E27"/>
    <SolidColorBrush x:Key="PanelElevatedBrush" Color="#2E362F"/>
    <SolidColorBrush x:Key="TextBrush" Color="#EDE6D6"/>
    <SolidColorBrush x:Key="MutedTextBrush" Color="#8C9389"/>
    <SolidColorBrush x:Key="BorderSubtleBrush" Color="#3A4239"/>
    <SolidColorBrush x:Key="AccentBrush" Color="#E0813F"/>
    <SolidColorBrush x:Key="AccentHoverBrush" Color="#EB9863"/>
    <SolidColorBrush x:Key="AccentPressedBrush" Color="#B4652C"/>
    <SolidColorBrush x:Key="DangerBrush" Color="#B4472B"/>
    <SolidColorBrush x:Key="DangerHoverBrush" Color="#C95B3E"/>
    <SolidColorBrush x:Key="OnlineBrush" Color="#8FAE63"/>

    <RadialGradientBrush x:Key="EmberGlowBrush">
        <GradientStop Color="#B3E0813F" Offset="0"/>
        <GradientStop Color="#00E0813F" Offset="1"/>
    </RadialGradientBrush>

    <!-- Plain Setters on ComboBox.Foreground are silently ignored by its
         default template (the selected-item text stays a fixed system
         color), which is why it read as unreadable grey-on-dark. A full
         ControlTemplate is the only reliable fix. -->
    <Style TargetType="ComboBoxItem">
        <Setter Property="Foreground" Value="{StaticResource TextBrush}"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="ComboBoxItem">
                    <Border x:Name="Bd" Background="Transparent" Padding="8,6">
                        <ContentPresenter/>
                    </Border>
                    <ControlTemplate.Triggers>
                        <Trigger Property="IsHighlighted" Value="True">
                            <Setter TargetName="Bd" Property="Background" Value="{StaticResource AccentBrush}"/>
                        </Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>

    <Style TargetType="ComboBox">
        <Setter Property="Background" Value="{StaticResource PanelElevatedBrush}"/>
        <Setter Property="Foreground" Value="{StaticResource TextBrush}"/>
        <Setter Property="BorderBrush" Value="{StaticResource BorderSubtleBrush}"/>
        <Setter Property="Padding" Value="10,8"/>
        <Setter Property="FontFamily" Value="Segoe UI"/>
        <Setter Property="FontSize" Value="13"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="ComboBox">
                    <Grid>
                        <ToggleButton x:Name="ToggleButton" Focusable="False" ClickMode="Press"
                                      IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}">
                            <ToggleButton.Template>
                                <ControlTemplate TargetType="ToggleButton">
                                    <Border x:Name="ComboBd" Background="{StaticResource PanelElevatedBrush}"
                                            BorderBrush="{StaticResource BorderSubtleBrush}"
                                            BorderThickness="1" CornerRadius="6">
                                        <Grid>
                                            <Grid.ColumnDefinitions>
                                                <ColumnDefinition Width="*"/>
                                                <ColumnDefinition Width="26"/>
                                            </Grid.ColumnDefinitions>
                                            <Path Grid.Column="1" Data="M0,0 L4,4 L8,0 Z" Fill="{StaticResource AccentBrush}"
                                                  HorizontalAlignment="Center" VerticalAlignment="Center"/>
                                        </Grid>
                                    </Border>
                                    <ControlTemplate.Triggers>
                                        <Trigger Property="IsMouseOver" Value="True">
                                            <Setter TargetName="ComboBd" Property="BorderBrush" Value="{StaticResource AccentBrush}"/>
                                        </Trigger>
                                    </ControlTemplate.Triggers>
                                </ControlTemplate>
                            </ToggleButton.Template>
                        </ToggleButton>
                        <ContentPresenter x:Name="ContentSite" IsHitTestVisible="False"
                                          Content="{TemplateBinding SelectionBoxItem}"
                                          ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"
                                          Margin="{TemplateBinding Padding}"
                                          VerticalAlignment="Center" HorizontalAlignment="Left"
                                          TextElement.Foreground="{StaticResource TextBrush}"/>
                        <Popup x:Name="Popup" Placement="Bottom" AllowsTransparency="True" Focusable="False"
                               PopupAnimation="Slide" IsOpen="{TemplateBinding IsDropDownOpen}">
                            <Border Background="{StaticResource PanelElevatedBrush}" BorderBrush="{StaticResource BorderSubtleBrush}"
                                    BorderThickness="1" CornerRadius="6" MaxHeight="200"
                                    MinWidth="{Binding ActualWidth, RelativeSource={RelativeSource TemplatedParent}}">
                                <ScrollViewer>
                                    <ItemsPresenter/>
                                </ScrollViewer>
                            </Border>
                        </Popup>
                    </Grid>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>

    <Style TargetType="TextBox">
        <Setter Property="Background" Value="{StaticResource PanelElevatedBrush}"/>
        <Setter Property="Foreground" Value="{StaticResource TextBrush}"/>
        <Setter Property="BorderBrush" Value="{StaticResource BorderSubtleBrush}"/>
        <Setter Property="Padding" Value="8,7"/>
        <Setter Property="FontFamily" Value="Consolas"/>
        <Setter Property="FontSize" Value="13"/>
        <Style.Triggers>
            <Trigger Property="IsFocused" Value="True">
                <Setter Property="BorderBrush" Value="{StaticResource AccentBrush}"/>
            </Trigger>
            <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Opacity" Value="0.5"/>
            </Trigger>
        </Style.Triggers>
    </Style>

    <Style x:Key="ActionButtonStyle" TargetType="Button">
        <Setter Property="Background" Value="{StaticResource AccentBrush}"/>
        <Setter Property="Foreground" Value="#1B211C"/>
        <Setter Property="FontFamily" Value="Segoe UI Semibold"/>
        <Setter Property="FontSize" Value="16"/>
        <Setter Property="Padding" Value="0,14"/>
        <Setter Property="BorderThickness" Value="0"/>
        <Setter Property="Cursor" Value="Hand"/>
        <Setter Property="HorizontalContentAlignment" Value="Center"/>
        <Setter Property="VerticalContentAlignment" Value="Center"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="Button">
                    <Grid RenderTransformOrigin="0.5,0.5">
                        <Grid.RenderTransform>
                            <ScaleTransform x:Name="PressScale"/>
                        </Grid.RenderTransform>
                        <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="6"/>
                        <Border x:Name="HoverOverlay" Background="{StaticResource AccentHoverBrush}" CornerRadius="6" Opacity="0"/>
                        <Border x:Name="PressOverlay" Background="{StaticResource AccentPressedBrush}" CornerRadius="6" Opacity="0"/>
                        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    </Grid>
                    <ControlTemplate.Triggers>
                        <Trigger Property="IsMouseOver" Value="True">
                            <Trigger.EnterActions>
                                <BeginStoryboard>
                                    <Storyboard>
                                        <DoubleAnimation Storyboard.TargetName="HoverOverlay" Storyboard.TargetProperty="Opacity" To="1" Duration="0:0:0.15"/>
                                    </Storyboard>
                                </BeginStoryboard>
                            </Trigger.EnterActions>
                            <Trigger.ExitActions>
                                <BeginStoryboard>
                                    <Storyboard>
                                        <DoubleAnimation Storyboard.TargetName="HoverOverlay" Storyboard.TargetProperty="Opacity" To="0" Duration="0:0:0.1"/>
                                    </Storyboard>
                                </BeginStoryboard>
                            </Trigger.ExitActions>
                        </Trigger>
                        <Trigger Property="IsPressed" Value="True">
                            <Trigger.EnterActions>
                                <BeginStoryboard>
                                    <Storyboard>
                                        <DoubleAnimation Storyboard.TargetName="PressOverlay" Storyboard.TargetProperty="Opacity" To="1" Duration="0:0:0.05"/>
                                        <DoubleAnimation Storyboard.TargetName="PressScale" Storyboard.TargetProperty="ScaleX" To="0.96" Duration="0:0:0.05"/>
                                        <DoubleAnimation Storyboard.TargetName="PressScale" Storyboard.TargetProperty="ScaleY" To="0.96" Duration="0:0:0.05"/>
                                    </Storyboard>
                                </BeginStoryboard>
                            </Trigger.EnterActions>
                            <Trigger.ExitActions>
                                <BeginStoryboard>
                                    <Storyboard>
                                        <DoubleAnimation Storyboard.TargetName="PressOverlay" Storyboard.TargetProperty="Opacity" To="0" Duration="0:0:0.1"/>
                                        <DoubleAnimation Storyboard.TargetName="PressScale" Storyboard.TargetProperty="ScaleX" To="1" Duration="0:0:0.1"/>
                                        <DoubleAnimation Storyboard.TargetName="PressScale" Storyboard.TargetProperty="ScaleY" To="1" Duration="0:0:0.1"/>
                                    </Storyboard>
                                </BeginStoryboard>
                            </Trigger.ExitActions>
                        </Trigger>
                    </ControlTemplate.Triggers>
                </Setter.Value>
        </Setter>
        <Style.Triggers>
            <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Opacity" Value="0.5"/>
            </Trigger>
        </Style.Triggers>
    </Style>

    <Style x:Key="LinkButtonStyle" TargetType="Button">
        <Setter Property="Background" Value="Transparent"/>
        <Setter Property="Foreground" Value="{StaticResource MutedTextBrush}"/>
        <Setter Property="FontFamily" Value="Segoe UI"/>
        <Setter Property="FontSize" Value="12"/>
        <Setter Property="BorderThickness" Value="0"/>
        <Setter Property="Cursor" Value="Hand"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="Button">
                    <Grid>
                        <Border x:Name="Bd" Background="Transparent" CornerRadius="4"/>
                        <Border x:Name="HoverOverlay" Background="#1AE0813F" CornerRadius="4" Opacity="0"/>
                        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="10,8"
                                           TextElement.Foreground="{TemplateBinding Foreground}"/>
                    </Grid>
                    <ControlTemplate.Triggers>
                        <Trigger Property="IsMouseOver" Value="True">
                            <Setter Property="Foreground" Value="{StaticResource AccentBrush}"/>
                            <Trigger.EnterActions>
                                <BeginStoryboard>
                                    <Storyboard>
                                        <DoubleAnimation Storyboard.TargetName="HoverOverlay" Storyboard.TargetProperty="Opacity" To="1" Duration="0:0:0.15"/>
                                    </Storyboard>
                                </BeginStoryboard>
                            </Trigger.EnterActions>
                            <Trigger.ExitActions>
                                <BeginStoryboard>
                                    <Storyboard>
                                        <DoubleAnimation Storyboard.TargetName="HoverOverlay" Storyboard.TargetProperty="Opacity" To="0" Duration="0:0:0.1"/>
                                    </Storyboard>
                                </BeginStoryboard>
                            </Trigger.ExitActions>
                        </Trigger>
                    </ControlTemplate.Triggers>
                </Setter.Value>
            </Setter>
        </Setter>
        <Style.Triggers>
            <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Opacity" Value="0.4"/>
            </Trigger>
        </Style.Triggers>
    </Style>

    <Style x:Key="IconGlyphStyle" TargetType="TextBlock">
        <Setter Property="FontFamily" Value="Segoe MDL2 Assets"/>
        <Setter Property="FontSize" Value="13"/>
        <Setter Property="Margin" Value="0,0,6,0"/>
        <Setter Property="VerticalAlignment" Value="Center"/>
    </Style>

    <!-- Sidecar status pill used on the Verity AI cards: muted grey by
         default, olive-green only when the text is exactly "LIT" (matches
         the same convention as the campfire StatusLabel on the home screen). -->
    <Style x:Key="StatusPillStyle" TargetType="TextBlock">
        <Setter Property="FontFamily" Value="Consolas"/>
        <Setter Property="FontWeight" Value="Bold"/>
        <Setter Property="FontSize" Value="11"/>
        <Setter Property="Padding" Value="10,4"/>
        <Setter Property="HorizontalAlignment" Value="Center"/>
        <Setter Property="Background" Value="{StaticResource BorderSubtleBrush}"/>
        <Setter Property="Foreground" Value="{StaticResource MutedTextBrush}"/>
        <Style.Triggers>
            <Trigger Property="Text" Value="LIT">
                <Setter Property="Background" Value="{StaticResource OnlineBrush}"/>
                <Setter Property="Foreground" Value="#1B211C"/>
            </Trigger>
        </Style.Triggers>
    </Style>

    <Style x:Key="BackButtonStyle" TargetType="Button">
        <Setter Property="Background" Value="Transparent"/>
        <Setter Property="Foreground" Value="{StaticResource MutedTextBrush}"/>
        <Setter Property="FontFamily" Value="Segoe MDL2 Assets"/>
        <Setter Property="FontSize" Value="16"/>
        <Setter Property="Width" Value="40"/>
        <Setter Property="Height" Value="40"/>
        <Setter Property="BorderThickness" Value="0"/>
        <Setter Property="Cursor" Value="Hand"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="Button">
                    <Grid>
                        <Border x:Name="Bd" Background="Transparent" CornerRadius="20"/>
                        <Border x:Name="HoverOverlay" Background="#1AE0813F" CornerRadius="20" Opacity="0"/>
                        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    </Grid>
                    <ControlTemplate.Triggers>
                        <Trigger Property="IsMouseOver" Value="True">
                            <Setter Property="Foreground" Value="{StaticResource TextBrush}"/>
                            <Trigger.EnterActions>
                                <BeginStoryboard>
                                    <Storyboard>
                                        <DoubleAnimation Storyboard.TargetName="HoverOverlay" Storyboard.TargetProperty="Opacity" To="1" Duration="0:0:0.15"/>
                                    </Storyboard>
                                </BeginStoryboard>
                            </Trigger.EnterActions>
                            <Trigger.ExitActions>
                                <BeginStoryboard>
                                    <Storyboard>
                                        <DoubleAnimation Storyboard.TargetName="HoverOverlay" Storyboard.TargetProperty="Opacity" To="0" Duration="0:0:0.1"/>
                                    </Storyboard>
                                </BeginStoryboard>
                            </Trigger.ExitActions>
                        </Trigger>
                    </ControlTemplate.Triggers>
                </Setter.Value>
            </Setter>
        </Setter>
        <Style.Triggers>
            <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Opacity" Value="0.4"/>
            </Trigger>
        </Style.Triggers>
    </Style>

    <Style x:Key="SendButtonStyle" TargetType="Button">
        <Setter Property="Background" Value="{StaticResource AccentBrush}"/>
        <Setter Property="Foreground" Value="#1B211C"/>
        <Setter Property="FontFamily" Value="Segoe UI Semibold"/>
        <Setter Property="FontSize" Value="13"/>
        <Setter Property="Padding" Value="16,0"/>
        <Setter Property="BorderThickness" Value="0"/>
        <Setter Property="Cursor" Value="Hand"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="Button">
                    <Grid>
                        <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="6"/>
                        <Border x:Name="HoverOverlay" Background="{StaticResource AccentHoverBrush}" CornerRadius="6" Opacity="0"/>
                        <Border x:Name="PressOverlay" Background="{StaticResource AccentPressedBrush}" CornerRadius="6" Opacity="0"/>
                        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    </Grid>
                    <ControlTemplate.Triggers>
                        <Trigger Property="IsMouseOver" Value="True">
                            <Trigger.EnterActions>
                                <BeginStoryboard>
                                    <Storyboard>
                                        <DoubleAnimation Storyboard.TargetName="HoverOverlay" Storyboard.TargetProperty="Opacity" To="1" Duration="0:0:0.15"/>
                                    </Storyboard>
                                </BeginStoryboard>
                            </Trigger.EnterActions>
                            <Trigger.ExitActions>
                                <BeginStoryboard>
                                    <Storyboard>
                                        <DoubleAnimation Storyboard.TargetName="HoverOverlay" Storyboard.TargetProperty="Opacity" To="0" Duration="0:0:0.1"/>
                                    </Storyboard>
                                </BeginStoryboard>
                            </Trigger.ExitActions>
                        </Trigger>
                        <Trigger Property="IsPressed" Value="True">
                            <Trigger.EnterActions>
                                <BeginStoryboard>
                                    <Storyboard>
                                        <DoubleAnimation Storyboard.TargetName="PressOverlay" Storyboard.TargetProperty="Opacity" To="1" Duration="0:0:0.05"/>
                                    </Storyboard>
                                </BeginStoryboard>
                            </Trigger.EnterActions>
                            <Trigger.ExitActions>
                                <BeginStoryboard>
                                    <Storyboard>
                                        <DoubleAnimation Storyboard.TargetName="PressOverlay" Storyboard.TargetProperty="Opacity" To="0" Duration="0:0:0.1"/>
                                    </Storyboard>
                                </BeginStoryboard>
                            </Trigger.ExitActions>
                        </Trigger>
                    </ControlTemplate.Triggers>
                </Setter.Value>
            </Setter>
        </Setter>
        <Style.Triggers>
            <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Opacity" Value="0.5"/>
            </Trigger>
        </Style.Triggers>
    </Style>

    <Style x:Key="LabelStyle" TargetType="TextBlock">
        <Setter Property="Foreground" Value="{StaticResource MutedTextBrush}"/>
        <Setter Property="FontFamily" Value="Segoe UI"/>
        <Setter Property="FontSize" Value="12"/>
        <Setter Property="Margin" Value="0,12,0,4"/>
    </Style>

    <Style x:Key="BrowseButtonStyle" TargetType="Button">
        <Setter Property="Background" Value="{StaticResource PanelElevatedBrush}"/>
        <Setter Property="Foreground" Value="{StaticResource TextBrush}"/>
        <Setter Property="FontFamily" Value="Segoe UI"/>
        <Setter Property="FontSize" Value="12"/>
        <Setter Property="Padding" Value="10,9"/>
        <Setter Property="BorderThickness" Value="0"/>
        <Setter Property="Cursor" Value="Hand"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="Button">
                    <Grid>
                        <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="5"/>
                        <Border x:Name="HoverOverlay" Background="{StaticResource AccentBrush}" CornerRadius="5" Opacity="0"/>
                        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    </Grid>
                    <ControlTemplate.Triggers>
                        <Trigger Property="IsMouseOver" Value="True">
                            <Setter Property="Foreground" Value="#1B211C"/>
                            <Trigger.EnterActions>
                                <BeginStoryboard>
                                    <Storyboard>
                                        <DoubleAnimation Storyboard.TargetName="HoverOverlay" Storyboard.TargetProperty="Opacity" To="1" Duration="0:0:0.15"/>
                                    </Storyboard>
                                </BeginStoryboard>
                            </Trigger.EnterActions>
                            <Trigger.ExitActions>
                                <BeginStoryboard>
                                    <Storyboard>
                                        <DoubleAnimation Storyboard.TargetName="HoverOverlay" Storyboard.TargetProperty="Opacity" To="0" Duration="0:0:0.1"/>
                                    </Storyboard>
                                </BeginStoryboard>
                            </Trigger.ExitActions>
                        </Trigger>
                    </ControlTemplate.Triggers>
                </Setter.Value>
            </Setter>
        </Setter>
    </Style>

    <Style x:Key="ToolButtonStyle" TargetType="Button">
        <Setter Property="Background" Value="{StaticResource PanelElevatedBrush}"/>
        <Setter Property="Foreground" Value="{StaticResource TextBrush}"/>
        <Setter Property="FontFamily" Value="Segoe UI"/>
        <Setter Property="FontSize" Value="12"/>
        <Setter Property="Padding" Value="12,11"/>
        <Setter Property="Margin" Value="0,0,10,8"/>
        <Setter Property="BorderThickness" Value="0"/>
        <Setter Property="Cursor" Value="Hand"/>
        <Setter Property="Tag" Value="{StaticResource AccentHoverBrush}"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="Button">
                    <Grid>
                        <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="5"/>
                        <Border x:Name="HoverOverlay" Background="{TemplateBinding Tag}" CornerRadius="5" Opacity="0"/>
                        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    </Grid>
                    <ControlTemplate.Triggers>
                        <Trigger Property="IsMouseOver" Value="True">
                            <Trigger.EnterActions>
                                <BeginStoryboard>
                                    <Storyboard>
                                        <DoubleAnimation Storyboard.TargetName="HoverOverlay" Storyboard.TargetProperty="Opacity" To="1" Duration="0:0:0.15"/>
                                    </Storyboard>
                                </BeginStoryboard>
                            </Trigger.EnterActions>
                            <Trigger.ExitActions>
                                <BeginStoryboard>
                                    <Storyboard>
                                        <DoubleAnimation Storyboard.TargetName="HoverOverlay" Storyboard.TargetProperty="Opacity" To="0" Duration="0:0:0.1"/>
                                    </Storyboard>
                                </BeginStoryboard>
                            </Trigger.ExitActions>
                        </Trigger>
                    </ControlTemplate.Triggers>
                </Setter.Value>
            </Setter>
        </Setter>
        <Style.Triggers>
            <Trigger Property="IsEnabled" Value="False">
                <Setter Property="Opacity" Value="0.4"/>
            </Trigger>
        </Style.Triggers>
    </Style>

    <Style TargetType="ListBoxItem">
        <Setter Property="Background" Value="Transparent"/>
        <Setter Property="Padding" Value="0"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="ListBoxItem">
                    <Grid>
                        <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="6"/>
                        <Border x:Name="HoverOverlay" Background="#1AE0813F" CornerRadius="6" Opacity="0"/>
                        <ContentPresenter/>
                    </Grid>
                    <ControlTemplate.Triggers>
                        <Trigger Property="IsMouseOver" Value="True">
                            <Trigger.EnterActions>
                                <BeginStoryboard>
                                    <Storyboard>
                                        <DoubleAnimation Storyboard.TargetName="HoverOverlay" Storyboard.TargetProperty="Opacity" To="1" Duration="0:0:0.15"/>
                                    </Storyboard>
                                </BeginStoryboard>
                            </Trigger.EnterActions>
                            <Trigger.ExitActions>
                                <BeginStoryboard>
                                    <Storyboard>
                                        <DoubleAnimation Storyboard.TargetName="HoverOverlay" Storyboard.TargetProperty="Opacity" To="0" Duration="0:0:0.1"/>
                                    </Storyboard>
                                </BeginStoryboard>
                            </Trigger.ExitActions>
                        </Trigger>
                        <Trigger Property="IsSelected" Value="True">
                            <Setter TargetName="Bd" Property="Background" Value="#33E0813F"/>
                        </Trigger>
                    </ControlTemplate.Triggers>
                </Setter.Value>
            </Setter>
        </Setter>
    </Style>

    <DataTemplate x:Key="WorldItemTemplate">
        <Border Background="{StaticResource PanelBrush}" CornerRadius="6" Margin="0,0,0,8" Padding="14,12"
                BorderBrush="{StaticResource BorderSubtleBrush}" BorderThickness="1">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel Grid.Column="0">
                    <TextBlock Text="{Binding Name}" Foreground="{StaticResource TextBrush}" FontSize="15" FontWeight="SemiBold"/>
                    <TextBlock Text="{Binding SizeLabel}" Foreground="{StaticResource MutedTextBrush}" FontSize="12" Margin="0,2,0,0"/>
                </StackPanel>
                <TextBlock Grid.Column="1" Text="{Binding BadgeText}" Foreground="{StaticResource OnlineBrush}"
                           VerticalAlignment="Center" FontSize="12" FontFamily="Consolas" FontWeight="Bold"/>
            </Grid>
        </Border>
    </DataTemplate>

    <Style x:Key="DialogButtonStyle" TargetType="Button">
        <Setter Property="Foreground" Value="#1B211C"/>
        <Setter Property="FontFamily" Value="Segoe UI Semibold"/>
        <Setter Property="FontSize" Value="13"/>
        <Setter Property="Padding" Value="16,8"/>
        <Setter Property="BorderThickness" Value="0"/>
        <Setter Property="Cursor" Value="Hand"/>
        <Setter Property="Tag" Value="{StaticResource AccentHoverBrush}"/>
        <Setter Property="Template">
            <Setter.Value>
                <ControlTemplate TargetType="Button">
                    <Grid RenderTransformOrigin="0.5,0.5">
                        <Grid.RenderTransform>
                            <ScaleTransform x:Name="PressScale"/>
                        </Grid.RenderTransform>
                        <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="5"/>
                        <Border x:Name="HoverOverlay" Background="{TemplateBinding Tag}" CornerRadius="5" Opacity="0"/>
                        <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    </Grid>
                    <ControlTemplate.Triggers>
                        <Trigger Property="IsMouseOver" Value="True">
                            <Trigger.EnterActions>
                                <BeginStoryboard>
                                    <Storyboard>
                                        <DoubleAnimation Storyboard.TargetName="HoverOverlay" Storyboard.TargetProperty="Opacity" To="1" Duration="0:0:0.15"/>
                                    </Storyboard>
                                </BeginStoryboard>
                            </Trigger.EnterActions>
                            <Trigger.ExitActions>
                                <BeginStoryboard>
                                    <Storyboard>
                                        <DoubleAnimation Storyboard.TargetName="HoverOverlay" Storyboard.TargetProperty="Opacity" To="0" Duration="0:0:0.1"/>
                                    </Storyboard>
                                </BeginStoryboard>
                            </Trigger.ExitActions>
                        </Trigger>
                        <Trigger Property="IsPressed" Value="True">
                            <Trigger.EnterActions>
                                <BeginStoryboard>
                                    <Storyboard>
                                        <DoubleAnimation Storyboard.TargetName="PressScale" Storyboard.TargetProperty="ScaleX" To="0.96" Duration="0:0:0.05"/>
                                        <DoubleAnimation Storyboard.TargetName="PressScale" Storyboard.TargetProperty="ScaleY" To="0.96" Duration="0:0:0.05"/>
                                    </Storyboard>
                                </BeginStoryboard>
                            </Trigger.EnterActions>
                            <Trigger.ExitActions>
                                <BeginStoryboard>
                                    <Storyboard>
                                        <DoubleAnimation Storyboard.TargetName="PressScale" Storyboard.TargetProperty="ScaleX" To="1" Duration="0:0:0.1"/>
                                        <DoubleAnimation Storyboard.TargetName="PressScale" Storyboard.TargetProperty="ScaleY" To="1" Duration="0:0:0.1"/>
                                    </Storyboard>
                                </BeginStoryboard>
                            </Trigger.ExitActions>
                        </Trigger>
                    </ControlTemplate.Triggers>
                </Setter.Value>
            </Setter>
        </Setter>
    </Style>

</ResourceDictionary>
```

- [ ] **Step 2: Commit**

```bash
git add _shared/gui/Theme.xaml
git commit -m "feat(gui): add shared Theme.xaml resource dictionary"
```

---

### Task 2: Wire the theme into the loader and strip per-screen duplication

**Files:**
- Modify: `Start-Gui.ps1:23-49`
- Modify: `_shared/gui/HomeScreen.xaml` (delete `<Grid.Resources>…</Grid.Resources>` block only — keep the `EmberBreathe` `Storyboard` and everything from `<Grid.RowDefinitions>` down)
- Modify: `_shared/gui/ConsoleScreen.xaml` (delete `<Grid.Resources>…</Grid.Resources>` block)
- Modify: `_shared/gui/AddServerScreen.xaml` (delete `<Grid.Resources>…</Grid.Resources>` block)
- Modify: `_shared/gui/ManageMapsScreen.xaml` (delete `<Grid.Resources>…</Grid.Resources>` block)
- Modify: `_shared/gui/PromptOverlay.xaml` (delete `<Grid.Resources>…</Grid.Resources>` block)

**Interfaces:**
- Consumes: `_shared/gui/Theme.xaml` from Task 1.
- Produces: every screen root (`$homeRoot`, `$mapsRoot`, `$addRoot`, `$consoleRoot`, `$overlayRoot`) has `Theme.xaml`'s dictionary merged into `.Resources.MergedDictionaries`, so `{StaticResource ...}` lookups in each screen's markup keep resolving after the screen's own `<Grid.Resources>` is deleted.

- [ ] **Step 1: Update `Get-ScreenXaml` in `Start-Gui.ps1` to merge the shared theme**

Replace lines 23-26 (the `Get-ScreenXaml` function) with:

```powershell
$script:theme = $null

function Get-ScreenXaml([string]$FileName) {
    [xml]$xamlXml = Get-Content -Path (Join-Path $root "_shared\gui\$FileName") -Raw
    $element = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xamlXml))

    if (-not $script:theme) {
        [xml]$themeXml = Get-Content -Path (Join-Path $root "_shared\gui\Theme.xaml") -Raw
        $script:theme = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $themeXml))
    }
    $element.Resources.MergedDictionaries.Add($script:theme)

    return $element
}
```

`Theme.xaml` is loaded once (`$script:theme` cached after the first call) and the *same* `ResourceDictionary` instance is merged into every screen root, including `MainWindow.xaml` itself (its call is `Get-ScreenXaml "MainWindow.xaml"` at line 32, unchanged) — `MainWindow` doesn't currently use any of these resources, but merging is harmless and future-proofs it.

- [ ] **Step 2: Delete the duplicated `<Grid.Resources>` block from `HomeScreen.xaml`**

Remove everything from `<Grid.Resources>` (line 6) through its matching `</Grid.Resources>` (line 232) in `_shared/gui/HomeScreen.xaml`, **except** keep the `EmberBreathe` `<Storyboard>` (lines 26-29) — move it to live directly on the `Ellipse.Triggers` where it's used instead of as a keyed resource, since it's only ever referenced there:

```xml
<Ellipse x:Name="EmberGlow" Width="160" Height="160" Fill="{StaticResource EmberGlowBrush}">
    <Ellipse.Triggers>
        <EventTrigger RoutedEvent="Ellipse.Loaded">
            <BeginStoryboard>
                <Storyboard RepeatBehavior="Forever">
                    <DoubleAnimation Storyboard.TargetProperty="Opacity"
                                      From="0.55" To="1.0" Duration="0:0:1.6" AutoReverse="True"/>
                </Storyboard>
            </BeginStoryboard>
        </EventTrigger>
    </Ellipse.Triggers>
</Ellipse>
```

(This replaces the old `<Ellipse.Triggers><EventTrigger ...><BeginStoryboard Storyboard="{StaticResource EmberBreathe}"/></EventTrigger></Ellipse.Triggers>` at lines 267-271 — same effect, no more dependency on a keyed resource that lived in `Grid.Resources`.)

After this step, `HomeScreen.xaml` starts directly with the `<Grid.RowDefinitions>` block (previously at line 234).

- [ ] **Step 3: Delete the duplicated `<Grid.Resources>` block from `ConsoleScreen.xaml`**

Remove `<Grid.Resources>` (line 6) through `</Grid.Resources>` (line 134) in `_shared/gui/ConsoleScreen.xaml`. File now starts directly at `<Grid.RowDefinitions>`.

- [ ] **Step 4: Delete the duplicated `<Grid.Resources>` block from `AddServerScreen.xaml`**

Remove `<Grid.Resources>` (line 6) through `</Grid.Resources>` (line 226) in `_shared/gui/AddServerScreen.xaml`.

- [ ] **Step 5: Delete the duplicated `<Grid.Resources>` block from `ManageMapsScreen.xaml`**

Remove `<Grid.Resources>` (line 6) through `</Grid.Resources>` (line 159) in `_shared/gui/ManageMapsScreen.xaml`.

- [ ] **Step 6: Delete the duplicated `<Grid.Resources>` block from `PromptOverlay.xaml`**

Remove `<Grid.Resources>` (line 6) through `</Grid.Resources>` (line 73) in `_shared/gui/PromptOverlay.xaml`.

- [ ] **Step 7: Manual smoke test**

Run `Start.bat` (or `pwsh -File Start-Gui.ps1` from the repo root). Confirm:
- The window opens with no XAML parse error.
- Home screen colors/fonts/buttons look unchanged from before this task (this task is pure plumbing — Task 4/5/6 do the visual bump).
- Navigate to Console, Add Server, Manage Maps — same check.
- Trigger a rename/delete prompt (Manage Maps → a world → any action that opens `PromptOverlay`) — confirm it still renders styled, not plain/unstyled.

- [ ] **Step 8: Commit**

```bash
git add Start-Gui.ps1 _shared/gui/HomeScreen.xaml _shared/gui/ConsoleScreen.xaml _shared/gui/AddServerScreen.xaml _shared/gui/ManageMapsScreen.xaml _shared/gui/PromptOverlay.xaml
git commit -m "refactor(gui): load Theme.xaml once, drop duplicated per-screen resources"
```

---

### Task 3: Make the window resizable and bump per-screen sizes

**Files:**
- Modify: `_shared/gui/MainWindow.xaml:5-6`
- Modify: `_shared/scripts/gui-helpers.ps1:83-94` (`Get-ScreenSize`)
- Modify: `tests/gui-helpers.tests.ps1:130-159` (`Get-ScreenSize` describe block)

**Interfaces:**
- Consumes: none new.
- Produces: `Get-ScreenSize -Screen <name>` returns the new bumped `Width`/`Height` values below — `Start-Gui.ps1:65-67` (`Show-Screen`) already calls this and assigns the result to `$window.Width`/`$window.Height`, unchanged.

New sizes (up from the current fixed values, still fits comfortably at 1366×768 and larger):

| Screen | Old | New |
|---|---|---|
| Home | 420×660 | 640×860 |
| ManageMaps | 440×580 | 480×640 |
| AddServer | 440×500 | 480×580 |
| Console | 560×640 | 640×720 |

- [ ] **Step 1: Update the failing test expectations first**

Edit `tests/gui-helpers.tests.ps1`, replace the `Get-ScreenSize` `Describe` block (lines 130-159) with:

```powershell
Describe "Get-ScreenSize" {

    It "returns the Home screen size" {
        $s = Get-ScreenSize -Screen "Home"
        $s.Width | Should Be 640
        $s.Height | Should Be 860
    }

    It "returns the Manage Maps screen size" {
        $s = Get-ScreenSize -Screen "ManageMaps"
        $s.Width | Should Be 480
        $s.Height | Should Be 640
    }

    It "returns the Add Server screen size" {
        $s = Get-ScreenSize -Screen "AddServer"
        $s.Width | Should Be 480
        $s.Height | Should Be 580
    }

    It "returns the Console screen size" {
        $s = Get-ScreenSize -Screen "Console"
        $s.Width | Should Be 640
        $s.Height | Should Be 720
    }

    It "throws a clear error for an unrecognized screen" {
        { Get-ScreenSize -Screen "Confused" } | Should Throw
    }
}
```

- [ ] **Step 2: Run the tests to verify the size assertions now fail**

Run: `Invoke-Pester tests/gui-helpers.tests.ps1 -TestName "Get-ScreenSize*"`
Expected: the first four `It` blocks FAIL (actual values are still the old ones); the "unrecognized screen" `It` still PASSes.

- [ ] **Step 3: Update `Get-ScreenSize` in `_shared/scripts/gui-helpers.ps1`**

Replace the `switch` body (lines 88-91) with:

```powershell
        "Home"       { return [PSCustomObject]@{ Width = 640; Height = 860 } }
        "ManageMaps" { return [PSCustomObject]@{ Width = 480; Height = 640 } }
        "AddServer"  { return [PSCustomObject]@{ Width = 480; Height = 580 } }
        "Console"    { return [PSCustomObject]@{ Width = 640; Height = 720 } }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Invoke-Pester tests/gui-helpers.tests.ps1 -TestName "Get-ScreenSize*"`
Expected: all 5 `It` blocks PASS.

- [ ] **Step 5: Make the window resizable in `MainWindow.xaml`**

In `_shared/gui/MainWindow.xaml`, replace line 5-6:

```xml
    Width="460" Height="720"
    ResizeMode="CanMinimize"
```

with:

```xml
    Width="640" Height="860"
    MinWidth="480" MinHeight="520"
    ResizeMode="CanResize"
```

(`Show-Screen` still overrides `Width`/`Height` on every navigation per `Get-ScreenSize`, so these are just the initial/startup values before `Show-Screen "Home"` runs at the bottom of `Start-Gui.ps1`. `MinWidth`/`MinHeight` are new — they cap how far the user can manually shrink the window regardless of which screen is active, chosen below the smallest screen's own size so no screen ever gets forced below its natural layout.)

- [ ] **Step 6: Manual smoke test**

Launch the app. Confirm: window is now resizable by dragging an edge/corner, doesn't shrink below roughly 480×520, and each screen still snaps to its own size when navigated to (Home is noticeably bigger, matching the table above).

- [ ] **Step 7: Commit**

```bash
git add tests/gui-helpers.tests.ps1 _shared/scripts/gui-helpers.ps1 _shared/gui/MainWindow.xaml
git commit -m "feat(gui): make the window resizable and bump per-screen sizes"
```

---

### Task 4: Redesign the Verity AI panel as sidecar cards (Option B)

**Files:**
- Modify: `_shared/gui/HomeScreen.xaml` (the `VerityAiPanel` border — was lines 361-429 pre-Task-2, find by `x:Name="VerityAiPanel"`)
- Modify: `Start-Gui.ps1` (Verity status-text assignments — search for `.StatusText.Text =`)

**Interfaces:**
- Consumes: `StatusPillStyle` from `Theme.xaml` (Task 1).
- Produces: keeps the exact same `x:Name`s `Start-Gui.ps1` already binds to (`VerityAiPanel`, `VerityOllamaStatusText`/`VerityOllamaButton`, `VerityKokoroStatusText`/`VerityKokoroButton`, `VerityWhisperStatusText`/`VerityWhisperButton`, `VerityAiStopAllButton`, `VerityApiKeyBox`, `VerityApiKeySaveButton`) — no `FindName` calls change. `StatusText` TextBlocks now hold *only* the state word/short message (e.g. `"OUT"`, `"LIT"`, `"Starting..."`), not `"Label: State"` — the label now lives as static XAML text on each card, so the code-behind that builds the combined string is trimmed to just the state fragment.

- [ ] **Step 1: Replace the Verity panel markup in `HomeScreen.xaml`**

Find the `<Border ... x:Name="VerityAiPanel" ...>` block and replace its entire contents (the inner `<Grid>...</Grid>`) with:

```xml
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <TextBlock Grid.Row="0" Text="LOCAL AI · VERITY" Foreground="{StaticResource MutedTextBrush}"
                       FontFamily="Segoe UI Semibold" FontSize="12" Margin="0,0,0,12"/>

            <UniformGrid Grid.Row="1" Rows="1" Columns="3" Margin="0,0,0,14">
                <Border Background="{StaticResource PanelElevatedBrush}" CornerRadius="8" Margin="0,0,8,0" Padding="12,14"
                        BorderBrush="{StaticResource BorderSubtleBrush}" BorderThickness="1">
                    <StackPanel HorizontalAlignment="Center">
                        <TextBlock Text="&#xE99A;" FontFamily="Segoe MDL2 Assets" FontSize="20" Foreground="{StaticResource TextBrush}" HorizontalAlignment="Center"/>
                        <TextBlock Text="Core LLM" Foreground="{StaticResource TextBrush}" FontFamily="Segoe UI Semibold" FontSize="12" HorizontalAlignment="Center" Margin="0,6,0,2"/>
                        <TextBlock Text="Ollama" Foreground="{StaticResource MutedTextBrush}" FontFamily="Segoe UI" FontSize="10" HorizontalAlignment="Center" Margin="0,0,0,8"/>
                        <TextBlock x:Name="VerityOllamaStatusText" Text="OUT" Style="{StaticResource StatusPillStyle}" Margin="0,0,0,8"/>
                        <Button x:Name="VerityOllamaButton" Content="START" Style="{StaticResource LinkButtonStyle}" HorizontalAlignment="Center"/>
                    </StackPanel>
                </Border>
                <Border Background="{StaticResource PanelElevatedBrush}" CornerRadius="8" Margin="0,0,8,0" Padding="12,14"
                        BorderBrush="{StaticResource BorderSubtleBrush}" BorderThickness="1">
                    <StackPanel HorizontalAlignment="Center">
                        <TextBlock Text="&#xE995;" FontFamily="Segoe MDL2 Assets" FontSize="20" Foreground="{StaticResource TextBrush}" HorizontalAlignment="Center"/>
                        <TextBlock Text="Voice out" Foreground="{StaticResource TextBrush}" FontFamily="Segoe UI Semibold" FontSize="12" HorizontalAlignment="Center" Margin="0,6,0,2"/>
                        <TextBlock Text="Kokoro" Foreground="{StaticResource MutedTextBrush}" FontFamily="Segoe UI" FontSize="10" HorizontalAlignment="Center" Margin="0,0,0,8"/>
                        <TextBlock x:Name="VerityKokoroStatusText" Text="OUT" Style="{StaticResource StatusPillStyle}" Margin="0,0,0,8"/>
                        <Button x:Name="VerityKokoroButton" Content="START" Style="{StaticResource LinkButtonStyle}" HorizontalAlignment="Center"/>
                    </StackPanel>
                </Border>
                <Border Background="{StaticResource PanelElevatedBrush}" CornerRadius="8" Padding="12,14"
                        BorderBrush="{StaticResource BorderSubtleBrush}" BorderThickness="1">
                    <StackPanel HorizontalAlignment="Center">
                        <TextBlock Text="&#xE720;" FontFamily="Segoe MDL2 Assets" FontSize="20" Foreground="{StaticResource TextBrush}" HorizontalAlignment="Center"/>
                        <TextBlock Text="Voice in" Foreground="{StaticResource TextBrush}" FontFamily="Segoe UI Semibold" FontSize="12" HorizontalAlignment="Center" Margin="0,6,0,2"/>
                        <TextBlock Text="Whisper" Foreground="{StaticResource MutedTextBrush}" FontFamily="Segoe UI" FontSize="10" HorizontalAlignment="Center" Margin="0,0,0,8"/>
                        <TextBlock x:Name="VerityWhisperStatusText" Text="OUT" Style="{StaticResource StatusPillStyle}" Margin="0,0,0,8"/>
                        <Button x:Name="VerityWhisperButton" Content="START" Style="{StaticResource LinkButtonStyle}" HorizontalAlignment="Center"/>
                    </StackPanel>
                </Border>
            </UniformGrid>

            <TextBlock Grid.Row="2" Text="GROQ API KEY (used when not local)" Foreground="{StaticResource MutedTextBrush}"
                       FontFamily="Segoe UI Semibold" FontSize="11" Margin="0,0,0,6"/>

            <Grid Grid.Row="3" Margin="0,0,0,12">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <PasswordBox Grid.Column="0" x:Name="VerityApiKeyBox" FontFamily="Consolas" FontSize="13"
                             Background="{StaticResource PanelElevatedBrush}" Foreground="{StaticResource TextBrush}"
                             BorderBrush="{StaticResource BorderSubtleBrush}" BorderThickness="1" Padding="8,6"
                             VerticalContentAlignment="Center"/>
                <Button Grid.Column="1" x:Name="VerityApiKeySaveButton" Content="SAVE" Style="{StaticResource LinkButtonStyle}"
                        Foreground="{StaticResource AccentBrush}" Margin="8,0,0,0"/>
            </Grid>

            <Button Grid.Row="4" x:Name="VerityAiStopAllButton" Content="STOP ALL" Style="{StaticResource LinkButtonStyle}"
                    Foreground="{StaticResource MutedTextBrush}" HorizontalAlignment="Right"/>
        </Grid>
```

Note the `TextBlock.Style` triggers used by `StatusPillStyle` (Task 1) key off `Text == "LIT"`; every other value (`"OUT"`, `"Starting..."`, `"Stopping..."`, error text) falls through to the default muted-grey pill.

- [ ] **Step 2: Trim the status text in `Start-Gui.ps1` to drop the now-redundant label prefix**

The card markup shows the sidecar's name statically now, so the `StatusText` should hold only the state fragment. Find and update these 4 assignments (search for `.StatusText.Text =`):

Change:
```powershell
            $svc.StatusText.Text = "$($svc.Label): $((Get-ServerStatusView -IsRunning $running).Label)"
```
to:
```powershell
            $svc.StatusText.Text = (Get-ServerStatusView -IsRunning $running).Label
```

Change:
```powershell
        $svc.StatusText.Text = "$($svc.Label): In use by another server, not stopping"
```
to:
```powershell
        $svc.StatusText.Text = "In use elsewhere"
```

Change:
```powershell
    $svc.StatusText.Text = "$($svc.Label): $(if ($running) { 'Stopping...' } else { 'Starting...' })"
```
to:
```powershell
    $svc.StatusText.Text = if ($running) { 'Stopping...' } else { 'Starting...' }
```

Change:
```powershell
        foreach ($s in $settled) { $s.Svc.StatusText.Text = "$($s.Svc.Label): Error - $($s.Reason)" }
```
to:
```powershell
        foreach ($s in $settled) { $s.Svc.StatusText.Text = "Error: $($s.Reason)" }
```

The `$svc.Label` field (`"Core LLM (Ollama)"` etc., set at `Start-Gui.ps1:86-88`) is no longer read anywhere after this change — leave the `Label` values in place since they're harmless and document what each `Key`/`Port` pair is for; don't delete the field itself.

- [ ] **Step 3: Manual smoke test**

Launch the app against a Verity-enabled instance (or whichever fixture/instance normally shows the panel). Confirm:
- Three cards render side by side, icon/name/status pill/button each legible, no overlapping text.
- Clicking Start/Stop on a card updates that card's pill text and color (green "LIT" vs grey "OUT") without affecting the other two cards.
- The "in use by another server" and error paths (trigger by starting the same sidecar from two instances, or forcing an error if there's a test hook) show sensible short text in the pill without wrapping awkwardly.
- Narrow the window toward `MinWidth` (480, from Task 3) — cards should stay readable (shrinking via `UniformGrid`'s equal-width columns) rather than clipping.

- [ ] **Step 4: Commit**

```bash
git add _shared/gui/HomeScreen.xaml Start-Gui.ps1
git commit -m "feat(gui): redesign Verity AI panel as sidecar cards"
```

---

### Task 5: Bump Home screen spacing/type scale outside the Verity panel

**Files:**
- Modify: `_shared/gui/HomeScreen.xaml`

**Interfaces:**
- Consumes: none new.
- Produces: no `x:Name` changes — every element `Start-Gui.ps1` binds to keeps its name.

- [ ] **Step 1: Wrap the screen content in a `ScrollViewer` as an overflow safety net**

The root `<Grid Margin="24">` (top of the file) becomes the child of a `ScrollViewer`, so that if content ever exceeds the window's height (e.g. a very long hint message), it scrolls instead of clipping/overlapping — this was the direct mechanism behind the original bug report. Wrap everything currently between the opening `<Grid ...>` tag and its Resources/RowDefinitions in:

```xml
<ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
<Grid Margin="32">
    <!-- ... existing Grid.RowDefinitions and row content ... -->
</Grid>
</ScrollViewer>
```

(Root element of the file changes from `Grid` to `ScrollViewer`; update the file's outermost tag accordingly — the `xmlns`/`xmlns:x` attributes move to the `ScrollViewer` tag.)

- [ ] **Step 2: Bump the title block**

```xml
    <StackPanel Grid.Row="0" Margin="0,0,0,24">
        <TextBlock Text="GAME SERVERS" Foreground="{StaticResource TextBrush}"
                   FontFamily="Segoe UI Black" FontSize="28" HorizontalAlignment="Center"/>
        <TextBlock Text="Your friends' world, one click away" Foreground="{StaticResource MutedTextBrush}"
                   FontFamily="Segoe UI" FontSize="13" HorizontalAlignment="Center" Margin="0,4,0,0"/>
    </StackPanel>
```

- [ ] **Step 3: Bump the server picker and status card spacing**

- `ComboBox` row: `Margin="0,0,0,16"` → `Margin="0,0,0,20"`.
- Status card `Border`: `Padding="16"` → `Padding="20"`.
- Address row `Border`: `Padding="12,10" Margin="0,14,0,0"` → `Padding="14,12" Margin="0,18,0,0"`, and its `TextBlock` `FontSize="13"` → `FontSize="14"`.

- [ ] **Step 4: Bump the primary action button and hint spacing**

- `ActionButton`: `Margin="0,20,0,0"` → `Margin="0,24,0,0"` (style itself already bumped via `Theme.xaml`'s `ActionButtonStyle` in Task 1).
- `HintText`: `FontSize="11"` → `FontSize="12"`, `Margin="0,10,0,0"` → `Margin="0,12,0,0"`.

- [ ] **Step 5: Bump the secondary actions row**

- `WrapPanel`: `Margin="0,4,0,0"` → `Margin="0,8,0,0"`.
- Each `LinkButtonStyle` button already gets more internal padding via `Theme.xaml` (Task 1's `LinkButtonStyle` keeps `Margin="10,8"` on its `ContentPresenter` — unchanged from before, already reasonably spaced).

- [ ] **Step 6: Bump the Verity panel's outer border**

The `VerityAiPanel` `Border` (from Task 4): `Padding="14" Margin="0,12,0,0"` → `Padding="18" Margin="0,16,0,0"`.

- [ ] **Step 7: Manual smoke test**

Launch the app, view Home with and without the Verity panel visible. Confirm nothing looks cramped, the `ScrollViewer` doesn't show a scrollbar in the normal case (content fits within 640×860), and resizing down toward `MinWidth`/`MinHeight` triggers scrolling gracefully instead of clipping.

- [ ] **Step 8: Commit**

```bash
git add _shared/gui/HomeScreen.xaml
git commit -m "polish(gui): bump Home screen spacing and type scale"
```

---

### Task 6: Bump spacing/type scale on Console, Add Server, and Manage Maps

**Files:**
- Modify: `_shared/gui/ConsoleScreen.xaml`
- Modify: `_shared/gui/AddServerScreen.xaml`
- Modify: `_shared/gui/ManageMapsScreen.xaml`

**Interfaces:**
- Consumes: none new.
- Produces: no `x:Name` changes.

- [ ] **Step 1: Bump `ConsoleScreen.xaml`**

- Root `Margin="20"` → `Margin="28"`.
- Title `TextBlock` `FontSize="20"` → `FontSize="22"`.
- `SubtitleText` `Margin="38,2,0,14"` → `Margin="40,4,0,18"`.
- Log `Border` `Padding="2"` stays (it's a hairline frame around the `TextBox`); the inner `TextBox` `Padding="10"` → `Padding="14"`, `FontSize="12"` → `FontSize="13"`.
- `HintText` `Margin="0,8,0,8"` → `Margin="0,12,0,12"`.
- `CommandBox`/`SendButton` row `Margin` unchanged (already tight by necessity — it's an input row).

- [ ] **Step 2: Bump `AddServerScreen.xaml`**

- Root `Margin="20"` → `Margin="28"`.
- Title `TextBlock` `FontSize="20"` → `FontSize="22"`; subtitle `Margin="0,2,0,0"` → `Margin="0,4,0,0"`.
- `LabelStyle` already bumped via `Theme.xaml` (Task 1: `Margin="0,12,0,4"`, was `0,10,0,4`).
- `ModpackDropZone` `MinHeight="92"` → `MinHeight="104"`; inner `StackPanel Margin="12"` → `Margin="16"`.
- `EulaCheck` `Margin="0,14,0,0"` → `Margin="0,18,0,0"`.
- `HintText` `Margin="0,10,0,10"` → `Margin="0,14,0,14"`.

- [ ] **Step 3: Bump `ManageMapsScreen.xaml`**

- Root `Margin="20"` → `Margin="28"`.
- Title `TextBlock` `FontSize="20"` → `FontSize="22"`; subtitle `Margin="38,2,0,14"` → `Margin="40,4,0,18"`.
- `HintText` `Margin="0,8,0,8"` → `Margin="0,12,0,12"`.
- `WorldItemTemplate` and `ToolButtonStyle` already bumped via `Theme.xaml` (Task 1).

- [ ] **Step 4: Manual smoke test**

Launch the app, visit Console, Add Server, and Manage Maps. Confirm consistent breathing room with the Home screen, nothing clipped, drop-zone and world list still function (drag-and-drop, switch/delete/import world) exactly as before.

- [ ] **Step 5: Commit**

```bash
git add _shared/gui/ConsoleScreen.xaml _shared/gui/AddServerScreen.xaml _shared/gui/ManageMapsScreen.xaml
git commit -m "polish(gui): bump spacing and type scale on remaining screens"
```

---

### Task 7: Full regression pass

**Files:** none (verification only)

- [ ] **Step 1: Run the full Pester suite**

Run: `Invoke-Pester tests/`
Expected: all specs PASS, including the updated `Get-ScreenSize` expectations from Task 3.

- [ ] **Step 2: Full manual walkthrough**

Launch `Start.bat` and, in one session:
1. Confirm Home renders correctly for both a Verity-enabled instance (cards visible) and a non-Verity instance (panel collapsed, no leftover gap).
2. Resize the window across its full range (`MinWidth`/`MinHeight` up to a large size) on Home with the Verity panel open — no clipping or overlap at any size.
3. Start/stop each of the 3 Verity sidecars from their cards; confirm status pills and buttons update correctly and independently.
4. Save a Groq API key via the panel; confirm it round-trips (reopen the app, field repopulates) — this exercises `Start-Gui.ps1:225-226` / `Set-VerityApiKey`, unchanged by this plan.
5. Navigate Home → Manage Maps → Add Server → Console and back, confirming each screen still resizes to its own dimensions and nothing regressed visually or functionally (create/switch/delete a world, drag a modpack, send a console command).
6. Trigger a `PromptOverlay` dialog (e.g. rename) — confirm it's still styled (this is the regression check for Task 2's resource-dictionary consolidation).

- [ ] **Step 3: Commit (only if the walkthrough surfaced fixes)**

If any step above required a code change, commit it separately with a message describing what regression it fixes. If the walkthrough passed clean, no commit needed for this task.
