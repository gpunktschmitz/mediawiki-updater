#!/bin/bash
#purpose: update mediawiki installation
#version: 0.3
#created: 2017-05-01 12:36:32
#author(s): Guenther Schmitz <https://www.gpunktschmitz.com>
#license: CC0 1.0 Universal <https://creativecommons.org/publicdomain/zero/1.0/>

# +VARIABLES
#TODO SKIP_RC_RELEASE=true
BACKUP_MYSQL_DB=true
MEDIAWIKIDIR=/home/gpunktschmitz/www/mediawiki_local/public
BACKUPDIR=/home/gpunktschmitz/BACKUP/GPUNKTMEDIAWIKIUPDATER
TMPDIR=/tmp/GPUNKTMEDIAWIKIUPDATERTMP
#TODO CHOWNUSER=wwwrun
#TODO CHOWNGROUP=wwwrun
# -VARIABLES

# +FUNCTIONS
#version compare function from the interweb (slightly modified to make the call more readable 'testvercomp "1.23.1" "<" "1.28.1"')
#https://stackoverflow.com/questions/4023830/how-compare-two-strings-in-dot-separated-version-format-in-bash?answertab=votes#tab-top
vercomp () {
    if [[ $1 == $2 ]]
    then
        return 0
    fi
    local IFS=.
    local i ver1=($1) ver2=($2)
    # fill empty fields in ver1 with zeros
    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++))
    do
        ver1[i]=0
    done
    for ((i=0; i<${#ver1[@]}; i++))
    do
        if [[ -z ${ver2[i]} ]]
        then
            # fill empty fields in ver2 with zeros
            ver2[i]=0
        fi
        if ((10#${ver1[i]} > 10#${ver2[i]}))
        then
            return 1
        fi
        if ((10#${ver1[i]} < 10#${ver2[i]}))
        then
            return 2
        fi
    done
    return 0
}

testvercomp () {
    vercomp $1 $3
    case $? in
        0) op='=';;
        1) op='>';;
        2) op='<';;
    esac
    if [[ $op != $2 ]]
    then
        return 0
    else
        return 1
    fi
}

backupmysqldb () {
        DB_TYPE=`grep -n "wgDBtype =" $MEDIAWIKIDIR/LocalSettings.php | awk -F '"' '{print $2}'`
        echo "database type: $DB_TYPE"

        if [ "$DB_TYPE" = "mysql" ]; then
                local DB_SERVER=$(grep "wgDBserver =" $MEDIAWIKIDIR/LocalSettings.php)
                local DB_SERVER=${DB_SERVER:15:-2}
                local DB_NAME=$(grep "wgDBname =" $MEDIAWIKIDIR/LocalSettings.php)
                local DB_NAME=${DB_NAME:13:-2}
                local DB_USER=$(grep "wgDBuser =" $MEDIAWIKIDIR/LocalSettings.php)
                local DB_USER=${DB_USER:13:-2}
                local DB_PW=$(grep "wgDBpassword =" $MEDIAWIKIDIR/LocalSettings.php)
                local DB_PW=${DB_PW:17:-2}

                echo "backing up database to '$BACKUPDIR/$DB_NAME.sql'"
                mysqldump -u $DB_USER -p${DB_PW} ${DB_NAME} > ${BACKUPDIR}/${DB_NAME}.sql
        else
                echo "database type is not 'mysql' (set BACKUP_MYSQL_DB to 'false' to continue without a backup created by this script) -> exiting"
                exit 1
        fi
}
# -FUNCTIONS

# +PROCESS
#check if "LocalSettings.php" exists
if [ ! -f $MEDIAWIKIDIR/LocalSettings.php ]; then
    echo "file 'LocalSettings.php' not found in directory '$MEDIAWIKIDIR'!"
    exit 1
fi


#get mediawiki version from MEDIAWIKIDIR
INSTALLED_VERSION=$(grep -n "wgVersion =" $MEDIAWIKIDIR/includes/DefaultSettings.php | awk -F "'" '{print $2}')
echo "currently installed version: $INSTALLED_VERSION"

#TODO
#LATEST_RELEASE="1.23"
# for $RELEASE in $LATEST_RELEASES; do
#       while [$RELEASE -ne $INSTALLED_VERSION]; do
#               if testvercomp $RELEASE ">" $INSTALLED_VERSION; then
#                       do_update
#                       break
#               fi
#       done
# done

#TODO pitfall
# releases: [[1.28.7], [1.29], [1.29-rc.1], [1.28.6]]
# installed: [1.28.6]
# version which should be installed: 1.29

#get releases from https://github.com/wikimedia/mediawiki/releases.atom
#TODO parse all and find latest one (if new version 1.30 and 1.31-rc.0 is released on one day and the RC is the latest one the script will currently not update to 1.30 but exit)
LATEST_RELEASE=$(wget -q -O- "https://github.com/wikimedia/mediawiki/releases.atom" | grep -o -P '<title>[^"]*' | sed "s/<title>//g" | sed "s/<\/title>//g" | sed -n 2p)
echo "latest release found: $LATEST_RELEASE"

#skip if release candidate
if grep "\-rc\." <<< $LATEST_RELEASE &>/dev/null; then
        #TODO handle RC releases (vercomp function currently cannot handle it)
        #if $SKIP_RC_RELEASE; then
                echo "latest release is a RC ($LATEST_RELEASE) -> exiting"
                exit 1
        #fi
fi

#check if latest version is newer
if testvercomp $LATEST_RELEASE ">" $INSTALLED_VERSION; then
        echo "no newer version found on the interweb -> exiting"
        exit 1
fi

#if tmp directory exists delete it/append "_{int}"
if [ -d $TMPDIR ]; then
        COUNTER=1
        TMPBASEDIR=$TMPDIR
        while [ -d $TMPDIR ]; do
                TMPDIR="${TMPBASEDIR}_${COUNTER}"
                COUNTER=$[COUNTER + 1]
        done
fi

#create tmp directory if not exists
if [ ! -d $TMPDIR ]; then
        mkdir $TMPDIR
        echo "temp directory '$BACKUPDIR' created"
fi

#create backup directory if not exists
if [ ! -d $BACKUPDIR ]; then
        mkdir $BACKUPDIR
        echo "backup directory '$BACKUPDIR' created"
fi

#create backup timestamp directory
TIMESTAMP=`date +%Y%m%d_%H%M%S`
BACKUPDIR="${BACKUPDIR}/${TIMESTAMP}"
echo $BACKUPDIR
if [ ! -d $BACKUPDIR ]; then
        mkdir $BACKUPDIR
        echo "backup directory '$BACKUPDIR' created"
fi

#backup mediawiki database
if $BACKUP_MYSQL_DB; then
        echo "trying to backup database"
        backupmysqldb
fi

#copy $MEDIAWIKIDIR to $BACKUPDIR
echo "copying '$MEDIAWIKIDIR' to '$BACKUPDIR/$INSTALLED_VERSION'"
mkdir ${BACKUPDIR}/${INSTALLED_VERSION}
cp -r ${MEDIAWIKIDIR}/* ${BACKUPDIR}/${INSTALLED_VERSION}/

#download new mediawiki version
echo "downloading version '$LATEST_RELEASE'"
wget https://github.com/wikimedia/mediawiki/archive/$LATEST_RELEASE.zip -O ${TMPDIR}/${LATEST_RELEASE}.zip -o /dev/null

#extract downloaded release
echo "extracting $LATEST_RELEASE"
unzip -oq ${TMPDIR}/${LATEST_RELEASE}.zip -d ${TMPDIR}

#get extracted directory
NEW_RELEASE_DIRECTORY=`ls -d ${TMPDIR}/*/`
echo "new release extracted to '${NEW_RELEASE_DIRECTORY}'"

#overwrite current installation
echo "updating installation with new files"
cp -r ${NEW_RELEASE_DIRECTORY}/* ${MEDIAWIKIDIR}

#updating dependencies
echo "deleting path ${MEDIAWIKIDIR}/vendor"
rm -r ${MEDIAWIKIDIR}/vendor
echo "cloning repo 'https://gerrit.wikimedia.org/r/p/mediawiki/vendor.git'"
git clone https://gerrit.wikimedia.org/r/p/mediawiki/vendor.git ${MEDIAWIKIDIR}/vendor

#remove old backup directory
echo "removing old backups (keeping last 3)"
ls -t -d ${BACKUPDIR}/*/  | grep -v "$(ls -t ${BACKUPDIR}/ | head -3)" | xargs rm -r

#remove tmp directory
echo "removing tmp directory"
echo "rm -r ${TMPDIR}"
rm -r ${TMPDIR}

#TODO chown

#execute update script
php ${MEDIAWIKIDIR}/maintenance/update.php --skip-external-dependencies
# -PROCESS

