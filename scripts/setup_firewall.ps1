# setup_firewall.ps1
# Copy Trading TCP System — Windows Firewall setup for Slave VPS
#
# This script opens the inbound TCP listen port on the Slave VPS
# so the Master can connect to it.
#
# Usage examples:
#   # Allow only Master IP on port 9501 (Slave 1):
#   .\setup_firewall.ps1 -Port 9501 -AllowedIPs @("1.2.3.4")
#
#   # Allow two slave ports for the same machine (if running two slaves):
#   .\setup_firewall.ps1 -Port 9501 -AllowedIPs @("1.2.3.4")
#   .\setup_firewall.ps1 -Port 9502 -AllowedIPs @("1.2.3.4")
#
#   # Open to all IPs (NOT recommended for production):
#   .\setup_firewall.ps1 -Port 9501

param(
    [int]$Port = 9501,
    [string[]]$AllowedIPs = @()
)

$RuleName = "CopyTrade TCP Port $Port"

# Remove existing rule with same name if present
Remove-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue
Write-Host "Removed existing rule '$RuleName' (if any)"

# Create new inbound rule
if ($AllowedIPs.Count -gt 0) {
    New-NetFirewallRule `
        -DisplayName $RuleName `
        -Direction Inbound `
        -LocalPort $Port `
        -Protocol TCP `
        -Action Allow `
        -RemoteAddress $AllowedIPs `
        -Description "Allow Copy Trading TCP Master connection on port $Port" | Out-Null
    Write-Host "Firewall rule created: port $Port, allowed IPs: $($AllowedIPs -join ', ')"
} else {
    New-NetFirewallRule `
        -DisplayName $RuleName `
        -Direction Inbound `
        -LocalPort $Port `
        -Protocol TCP `
        -Action Allow `
        -Description "Allow Copy Trading TCP Master connection on port $Port (all IPs)" | Out-Null
    Write-Warning "CAUTION: No IP filter set. Any host can connect to port $Port."
    Write-Host "Firewall rule created: port $Port open to all IPs"
}

# Display the created rule
Write-Host ""
Write-Host "--- Rule Details ---"
Get-NetFirewallRule -DisplayName $RuleName | Format-List DisplayName, Direction, Action, Enabled

Write-Host ""
Write-Host "Done. Port $Port is now open for inbound TCP connections."
Write-Host "Test from Master VPS: Test-NetConnection -ComputerName <SlaveIP> -Port $Port"
