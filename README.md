# mediawiki-updater

This script is a meant to be a tool for the lazy admin to update mediawiki to the latest stable version. It is not yet "feature complete" (see the "#TODO" comments) but works for now. It was intended to also work when run as cron job (for the laziest of us).

mediawiki-updater does the following:

* check for a new version
* backup MySQL database
* backup current installation
* download new MediaWiki release
* extract new release to temporary folder
* update current installation with new release
* deletes the directory "vendor"
* fetch new external libraries via git into directory "vendor"
* remove old backups (but keeps the latest 3)
* run the "maintenance/update.php" script

## requirements

### bash script
The bash script uses the following executables:

* git
* php
* grep
* sed
* awk
* tar
* wget
* unzip
* gunzip
* mysqldump
* mkdir
* xargs
* pushd
* popd
* head

### PowerShell script
The PowerShell script uses the following executables:

* mysqldump
* git
* php
