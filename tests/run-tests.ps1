# Determine the path to this script (we'll use this to figure out relative positions of other files)
$SOURCE = $MyInvocation.MyCommand.Path

# ------ Setting all the paths required

Write-Host "> Setting all the paths required..."

# Tests folder 
# e.g quarto-cli/tests folder
$SCRIPT_PATH = Split-Path -Path $SOURCE

# Project folder
# e.g quarto-cli project folder 
$QUARTO_ROOT = Split-Path $SCRIPT_PATH

# Source folder
# e.g quarto-cli/src folder
$QUARTO_SRC_DIR= Join-Path $QUARTO_ROOT "src"

# .sh version has source $SCRIPT_PATH/../package/scripts/common/utils.sh for configure.sh requirements
# but configure.cmd does not need it

# Quarto binary folder
# e.g quarto-cli/package/dist/bin
$QUARTO_BIN_PATH = Join-Path $QUARTO_ROOT "package" "dist" "bin"
# Deno binary in tools/
$QUARTO_DENO = Join-Path $QUARTO_BIN_PATH "tools" "deno.exe"

# Shared resource folder
# e.g quarto-cli/src/resources
$QUARTO_SHARE_PATH = Join-Path $QUARTO_ROOT "src" "resources"


# ----- Restoring tests environnment ---------

If ( $null -eq $Env:GITHUB_ACTION -and $null -eq $Env:QUARTO_TESTS_NO_CONFIG ) {
  Write-Host "> Checking and configuring environment for tests"
  . ./configure-test-env.ps1
}

# ----- Preparing running tests ------------


Write-Host "> Preparing running tests..."

# Exporting some variables with paths as env var required for running quarto
$Env:QUARTO_ROOT = $QUARTO_ROOT
$Env:QUARTO_BIN_PATH = $QUARTO_BIN_PATH
$Env:QUARTO_SHARE_PATH = $QUARTO_SHARE_PATH

# Activated debug mode by default for stack trace
$Env:QUARTO_DEBUG = "true" 

# Preparing running Deno with default arguments

$QUARTO_IMPORT_ARGMAP="--importmap=$(Join-Path $QUARTO_SRC_DIR "dev_import_map.json")"
$QUARTO_DENO_OPTIONS="--config test-conf.json --unstable --allow-read --allow-write --allow-run --allow-env --allow-net --check"

# Parsing argument passed to the script

# We Don't use `param()` or `$args` - instead, we do our own argument parsing because
# PowerShell quietly strips -- from the list of arguments and `--` is need for Deno to pass argument to the script
# Code adapted from: https://stackoverflow.com/questions/56750826/how-to-use-dash-argument-in-powershell

# Extract the argument list from the invocation command line.
$argList = ($MyInvocation.Line -replace ('^.*' + [regex]::Escape($MyInvocation.InvocationName)) -split '[;|]')[0].Trim()

# Use Invoke-Expression with a Write-Output call to parse the raw argument list,
# performing evaluation and splitting it into an array:
$customArgs = if ($argList) { @(Invoke-Expression "Write-Output -- $argList") } else { @() }

# ---- Running tests with Deno -------

$DENO_ARGS = @()
$DENO_ARGS += "test"
$DENO_ARGS += -split $QUARTO_DENO_OPTIONS
# Allow to pass some more options - empty by default
If ($QUARTO_DENO_EXTRA_OPTIONS -ne $null) { 
  $DENO_ARGS += -split $QUARTO_DENO_EXTRA_OPTIONS
}
$DENO_ARGS += -split $QUARTO_IMPORT_ARGMAP
$DENO_ARGS += $customArgs

# Activate python virtualenv
# set QUARTO_TESTS_FORCE_NO_PIPENV env var to not activate the virtalenv manage by pipenv for the project
If ($null -eq $Env:QUARTO_TESTS_FORCE_NO_PIPENV) {
  # Save possible activated virtualenv for later restauration
  $OLD_VIRTUAL_ENV=$VIRTUAL_ENV
  Write-Host "> Activating virtualenv for Python tests in Quarto"
  . "$(pipenv --venv)/Scripts/activate.ps1"
  $quarto_venv_activated = $true
}


Write-Host "> Running tests with `"$QUARTO_DENO $DENO_ARGS`" "

& $QUARTO_DENO $DENO_ARGS

$SUCCESS = $?
$DENO_EXIT_CODE = $LASTEXITCODE

# Add Coverage handling

If($quarto_venv_activated) {
  Write-Host "> Exiting virtualenv activated for tests"
  deactivate
  Remove-Variable quarto_venv_activated
}
If($null -ne $OLD_VIRTUAL_ENV) {
  Write-Host "> Reactivating original virtualenv"
  . "$OLD_VIRTUAL_ENV/Scripts/activate.ps1"
  Remove-Variable OLD_VIRTUAL_ENV
}

Exit $DENO_EXIT_CODE
