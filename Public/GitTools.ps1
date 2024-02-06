#requires -version 5.0

Set-StrictMode -Version 3.0

class GitTools {
    [string] $UserName
    [SecureString] $Password
    [string] $WorkingDirectory
    [uri] $RemoteRepositoryUri
    hidden [string] $GitExeLocation
    hidden [string] $CommitMessage
    hidden [CustomOutput] $customOutput
    
    GitTools([string] $userName, [SecureString] $password, [string] $WorkingDirectory, [uri] $remoteRepositoryUri) {
        $this.Init($userName, $password, $WorkingDirectory, $remoteRepositoryUri, "Console")
    }

    GitTools([string] $userName, [SecureString] $password, [string] $WorkingDirectory, [uri] $remoteRepositoryUri, [string] $outputType) {
        $this.Init($userName, $password, $WorkingDirectory, $remoteRepositoryUri, $outputType)
    }
    
    hidden [void] Init([string] $userName, [SecureString] $password, [string] $WorkingDirectory, [uri] $remoteRepositoryUri, [string] $outputType) {
        $this.UserName = $userName
        $this.Password = $password
        $this.WorkingDirectory = $workingDirectory
        $this.customOutput = [CustomOutput]::new($outputType)

        $ub = New-Object System.UriBuilder -ArgumentList $remoteRepositoryUri
        $ub.UserName = $userName
        $ub.Password = [System.Runtime.InteropServices.Marshal]::PtrToStringUni([System.Runtime.InteropServices.Marshal]::SecureStringToCoTaskMemUnicode($password))    
        $this.RemoteRepositoryUri = $ub.Uri
        
        $config = Get-Configuration -configurationFile $PSScriptRoot\config\GitToolsConfig.json
        $this.GitExeLocation = $config.GitExeLocation
        if (![System.IO.File]::Exists($this.GitExeLocation + "bin\git.exe")) {
            throw (New-Object System.IO.FileNotFoundException("GIT not found: $this.GitExeLocation", $this.GitExeLocation))
        }

        $this.CommitMessage = '"' + $config.CommitMessage + " " + (Get-Date -Format yyyyMMddThhmm) + '"'
        
        $this.InitWorkingDirectory()
    }
    
    [void] PushGit() {
        $outputText = ""
        $this.InvokeGit("add .", @("add", "."))
        $this.InvokeGit("commit", @("commit", "-m", $this.CommitMessage))
        $this.InvokeGit("push origin master", @("push", "origin", "master"))
    }
    
    [void] PullGit() {
        $outputText = ""
        $this.InvokeGit("pull", @("pull"))
    }
    
    [void] CloneGit() {
        $this.InvokeGit("clone", @("clone", $this.remoteRepositoryUri))
    }
    
    [uri] GetRepositoryUri() {
        $outputText = $this.InvokeGit("get remote.origin.url", @("config", "--get", "remote.origin.url"))
        if (!$this.isUri($outputText)) {
            throw $outputText
        }
        else {
            return [uri]$outputText
        }
    }

    hidden [void] InitWorkingDirectory() {
        if (!(Test-Path (Split-Path $this.WorkingDirectory))) {
            New-Item (Split-Path $this.WorkingDirectory) -ItemType Directory
        }

        if ($this.WorkingDirectoryIsEmpty()) {
            $this.CloneGit()
        } 
        else {
            $this.TestWorkingDirectory()
            $this.PullGit()
        }
    }
    
    hidden [bool] WorkingDirectoryIsEmpty() {
        if ( (Get-ChildItem $this.WorkingDirectory -Force | Measure-Object).Count -eq 0) {
            return $true
        }
        else {
            return $false
        }
    }

    hidden [void] TestWorkingDirectory() {
        $gitUri = $this.GetRepositoryUri()

        if (($gitUri.Host + $gitUri.PathAndQuery) -ne ($this.remoteRepositoryUri.Host + $this.remoteRepositoryUri.PathAndQuery)) {
            throw "Directory " + $this.WorkingDirectory + " is either not empty or not pointed to the right repository."
        }
    }

    hidden [string] InvokeGit([string] $reason, [string[]] $argumentsList) {
        try {
            if ($argumentsList[0] -eq "clone") {
                Set-Location -Path (Split-Path $this.WorkingDirectory)
            }
            else {
                Set-Location -Path $this.WorkingDirectory
            }
            $currWorkingDirectory = Get-Location
            

            $gitPath = $this.GitExeLocation + "bin\git.exe"
            $gitErrorPath = Join-Path $env:TEMP "stderr.txt"
            $gitOutputPath = Join-Path $env:TEMP "stdout.txt"
            if ($gitPath.Count -gt 1) {
                $gitPath = $gitPath[0]
            }

            $this.customOutput.WriteCustomOutput("[Git][$Reason] Begin")
            $this.customOutput.WriteCustomOutput("[Git][$Reason] gitPath=$gitPath")
            $this.customOutput.WriteCustomOutput("[Git][$Reason] workingDirectory=$currWorkingDirectory")
            $this.customOutput.WriteCustomOutput("git $ArgumentsList")
            $process = Start-Process $gitPath -ArgumentList $argumentsList -NoNewWindow -PassThru -Wait -RedirectStandardError $gitErrorPath -RedirectStandardOutput $gitOutputPath
            $outputText = (Get-Content $gitOutputPath)
            $outputText | ForEach-Object { $this.customOutput.WriteCustomOutput($_) }

            if ($process.ExitCode -ne 0) {
                $this.customOutput.WriteCustomOutput("[Git][$Reason] process.ExitCode=$($process.ExitCode)")
                $errorText = $(Get-Content $gitErrorPath)
                $errorText | ForEach-Object { $this.customOutput.WriteCustomOutput($_) }

                if ($errorText -ne $null) {
                    throw $process.ExitCode
                }
            }
            
            return $outputText
        }
        catch {
            $this.customOutput.WriteCustomOutput("[Git][$Reason] Exception $_")
            throw
        }
    }

    hidden [bool] isUri($address) {
        return ($address -as [System.URI]).AbsoluteURI -ne $null
    }
}