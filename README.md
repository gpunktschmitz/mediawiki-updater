# mediawiki-updater

This script is a meant to be a tool for the lazy admin to update mediawiki to the latest stable version. It is not yet "feature complete" (see the "#TODO" comments) but works for now. It was intended to also work when run as cron job (for the laziest of us).

mediawiki-updater does the following:

* check for a new version
* backup MySQL database
* move current installation to backup path
* download new MediaWiki release
* extract new release to temporary folder
* copy new release
* copying LocalSettings.php from previous version
* copying images from previous version
* copying skins from previous version
* copying extensions from previous version
* remove old backups (but keeps the latest 3)
* run the "maintenance/update.php" script

## requirements

### bash script
The bash script uses the following executables:

* awk
* basename
* grep
* head
* mkdir
* mysqldump
* php
* sed
* tar
* wget
