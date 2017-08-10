#purpose: backup mediawiki installation and update to latest release
#author(s): Guenther Schmitz <https://www.gpunktschmitz.com>
#license: CC0 1.0 Universal <https://creativecommons.org/publicdomain/zero/1.0/>

# +VARIABLES
#TODO $SKIP_RC_RELEASE=$true
$BACKUP_MYSQL_DB=$true
$MEDIAWIKIDIR="C:\xampp\htdocs\mw"
$BACKUPDIR="D:\BACKUP"
$BACKUPBASEDIR=$BACKUPDIR
$TMPDIR="C:\tmp\GPUNKTMEDIAWIKIUPDATERTMP"
$MYSQLDUMPEXECUTABLE="C:\xampp\mysql\bin\mysqldump.exe"
$GITEXECUTABLE="C:\cygwin64\usr\libexec\git-core\git.exe"
$PHPEXECUTABLE="C:\xampp\php\php.exe"
#TODO $CHOWNUSER="wwwrun"
#TODO $CHOWNGROUP="wwwrun"
# -VARIABLES

# +FUNCTIONS
function backupmysqldb() {
    [string]$DB_TYPE=Get-Content "${MEDIAWIKIDIR}\LocalSettings.php" | Select-String -Pattern "wgDBtype ="
    $DB_TYPE=$DB_TYPE.Substring(13,$DB_TYPE.Length-15)
    echo "database type: $DB_TYPE"

    if($DB_TYPE -eq "mysql") {
        [string]$DB_SERVER=$(Get-Content "${MEDIAWIKIDIR}\LocalSettings.php" | Select-String -Pattern "wgDBserver =")
        $DB_SERVER=$DB_SERVER.Substring(15,$DB_SERVER.Length-17)
        
        [string]$DB_NAME=$(Get-Content "${MEDIAWIKIDIR}\LocalSettings.php" | Select-String -Pattern "wgDBname =")
        $DB_NAME=$DB_NAME.Substring(13,$DB_NAME.Length-15)
        
        [string]$DB_USER=$(Get-Content "${MEDIAWIKIDIR}\LocalSettings.php" | Select-String -Pattern "wgDBuser =")
        $DB_USER=$DB_USER.Substring(13,$DB_USER.Length-15)
        
        [string]$DB_PW=$(Get-Content "${MEDIAWIKIDIR}\LocalSettings.php" | Select-String -Pattern "wgDBpassword =")
        $DB_PW=$DB_PW.Substring(17,$DB_PW.Length-19)

        echo "backing up database to '${BACKUPDIR}\$DB_NAME.sql'"
        if(-not $DB_PW) {
            Start-Process -FilePath "cmd" -ArgumentList "/c $MYSQLDUMPEXECUTABLE -u $DB_USER $DB_NAME > ${BACKUPDIR}\${DB_NAME}.sql" -Wait
        } else {
            Start-Process -FilePath "cmd" -ArgumentList "/c $MYSQLDUMPEXECUTABLE -u $DB_USER -p$DB_PW $DB_NAME > ${BACKUPDIR}\${DB_NAME}.sql" -Wait
        }
    } else {
        echo "database type is not 'mysql' (set BACKUP_MYSQL_DB to 'false' to continue without a backup created by this script) -> exiting"
        exit 1
    }
}
# -FUNCTIONS

# +PROCESS
#check if "LocalSettings.php" exists
if (-not (Test-Path "${MEDIAWIKIDIR}\LocalSettings.php" )) {
    echo "file 'LocalSettings.php' not found in directory '$MEDIAWIKIDIR'!"
    exit 1
}

#get mediawiki version from MEDIAWIKIDIR
[string]$INSTALLED_VERSION=Get-Content "${MEDIAWIKIDIR}\includes\DefaultSettings.php" | Select-String -Pattern "wgVersion ="
$INSTALLED_VERSION=$INSTALLED_VERSION.Substring(14, $INSTALLED_VERSION.Length-16)
echo "currently installed version: $INSTALLED_VERSION"

[version]$LATEST_RELEASE=$INSTALLED_VERSION

#get releases from https://github.com/wikimedia/mediawiki/releases.atom
[xml]$LATEST_RELEASES = (New-Object System.Net.WebClient).DownloadString("https://github.com/wikimedia/mediawiki/releases.atom")
foreach($RELEASE in $LATEST_RELEASES.feed.entry) {
    $RELEASE_VERSION = $RELEASE.title
    #skip if release candidate
    if($RELEASE_VERSION -notmatch '-rc') {
        [version]$RELEASE_VERSION_COMPARE = $RELEASE_VERSION
        if($RELEASE_VERSION_COMPARE -gt $LATEST_RELEASE) {
            $LATEST_RELEASE=[version]$RELEASE_VERSION
        }
    }
}

echo "latest release found: $LATEST_RELEASE"

#check if latest version is newer
if($LATEST_RELEASE -le [version]$INSTALLED_VERSION) {
    echo "no newer version found on the interweb -> exiting"
    exit 0
}

#if tmp directory exists append "_{int}"
if(Test-Path -LiteralPath $TMPDIR) {
    $COUNTER=1
    $TMPBASEDIR=$TMPDIR
    while(Test-Path -LiteralPath $TMPDIR) {
        $TMPDIR="${TMPBASEDIR}_${COUNTER}"
        $COUNTER++
    }
}

#create tmp directory if not exists
if(-not(Test-Path -LiteralPath $TMPDIR)) {
    $TMPVAR=New-Item -ItemType 'directory' -Path $TMPDIR
    echo "temp directory '$TMPDIR' created"
}

#create backup directory if not exists
if(-not(Test-Path -LiteralPath $BACKUPDIR)) {
    $TMPVAR=mkdir $BACKUPDIR
    echo "backup directory '$BACKUPDIR' created"
}

#create backup timestamp directory
$TIMESTAMP=$(Get-Date -Format 'yyyyMMdd_HHmmss')
$BACKUPDIR=$BACKUPDIR, $TIMESTAMP -join "\"
if(-not(Test-Path -LiteralPath $BACKUPDIR)) {
    $TMPVAR=mkdir $BACKUPDIR
    echo "backup directory '$BACKUPDIR' created"
} else {
    echo "backup directory '$BACKUPDIR' already exists?! try restarting the script." 
    exit 1
}

#backup mediawiki database
if($BACKUP_MYSQL_DB) {
    echo "trying to backup database"
    backupmysqldb
}

#copy $MEDIAWIKIDIR to $BACKUPDIR
$BACKUPDIR=$BACKUPDIR, $INSTALLED_VERSION -join "\"
echo "copying '$MEDIAWIKIDIR' to '$BACKUPDIR'"
$TMPVAR=mkdir $BACKUPDIR
Copy-Item -Path ${MEDIAWIKIDIR}\* -Destination $BACKUPDIR -Recurse

#download new mediawiki version
echo "downloading version: $LATEST_RELEASE"
$TMPZIPFILE=$TMPDIR,$LATEST_RELEASE -join "\"
$TMPZIPFILE=$TMPZIPFILE,"zip" -join "."
$URL="https://github.com/wikimedia/mediawiki/archive/",$LATEST_RELEASE,".zip" -join "" 
Invoke-WebRequest -Uri $URL -OutFile $TMPZIPFILE

if((Test-Path -Path $TMPZIPFILE) -and ((Get-Item -Path $TMPZIPFILE).length -gt 1MB)) {
    #extract downloaded release
    echo "extracting $LATEST_RELEASE"
    Expand-Archive -LiteralPath $TMPZIPFILE -DestinationPath $TMPDIR

    #get extracted directory
    $NEW_RELEASE_DIRECTORY=$(Get-ChildItem -Path $TMPDIR | ?{$_.PSIsContainer}).FullName
    echo "new release extracted to '$NEW_RELEASE_DIRECTORY'"

    #overwrite current installation
    echo "updating installation with new files"
    Copy-Item -Path ${NEW_RELEASE_DIRECTORY}\* -Destination $MEDIAWIKIDIR -Recurse -Force

    #updating dependencies
    echo "deleting path '${MEDIAWIKIDIR}\vendor'"
    Remove-Item -LiteralPath "${MEDIAWIKIDIR}\vendor" -Recurse -Force
    echo "cloning repo 'https://gerrit.wikimedia.org/r/p/mediawiki/vendor.git'"
    Start-Process -FilePath "cmd" -ArgumentList "/c $GITEXECUTABLE clone https://gerrit.wikimedia.org/r/p/mediawiki/vendor.git ${MEDIAWIKIDIR}\vendor" -Wait

    #remove old backup directory
    echo "removing old backups (keeping last 3)"
    $COUNTER=0
    $BACKUPS=Get-ChildItem -LiteralPath $BACKUPBASEDIR | ?{$_.PSIsContainer} | Sort-Object -Property CreationTime -Descending
    if($BACKUPS.Count -gt 3) {
        foreach($BACKUPFOLDER in $BACKUPS) {
            $COUNTER++
            if($COUNTER -gt 3) {
                Remove-Item -LiteralPath $BACKUPFOLDER.FullName -Recurse -Force
            }
        }
    }
    
    #remove tmp directory
    echo "removing tmp directory"
    Remove-Item -LiteralPath $TMPDIR -Recurse -Force

    #TODO chown

    #execute update script
    Start-Process -FilePath "cmd" -ArgumentList "/c $PHPEXECUTABLE ${MEDIAWIKIDIR}\maintenance\update.php --skip-external-dependencies" -Wait

    exit 0
    # -PROCESS
} else {
    echo "download ($TMPZIPFILE) seems not to be valid"
    exit 1
}
