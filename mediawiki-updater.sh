#!/bin/bash
#purpose: backup mediawiki installation and update to latest release
#author(s): Guenther Schmitz <https://www.gpunktschmitz.com>
#license: CC0 1.0 Universal <https://creativecommons.org/publicdomain/zero/1.0/>

# +VARIABLES
#TODO SKIP_RC_RELEASE=true
BACKUP_MYSQL_DB=true
MEDIAWIKIDIR=/home/gpunktschmitz/www/mediawiki_local/public2
BACKUPDIR=/home/gpunktschmitz/BACKUP/GPUNKTMEDIAWIKIUPDATER
TMPDIR=/tmp/GPUNKTMEDIAWIKIUPDATERTMP
#--
AWKEXECUTABLE=$(which awk)
BASENAMEEXECUTABLE=$(which basename)
#TODO CHOWNUSER=wwwrun
#TODO CHOWNGROUP=wwwrun
GREPEXECUTABLE=$(which grep)
HEADEXECUTABLE=$(which head)
MKDIREXECUTABLE=$(which mkdir)
MYSQLDUMPEXECUTABLE=$(which mysqldump)
PHPEXECUTABLE=$(which php)
SEDEXECUTABLE=$(which sed)
TAREXECUTABLE=$(which tar)
WGETEXECUTABLE=$(which wget)
# -VARIABLES

# +FUNCTIONS
#version compare function from the interweb (slightly modified to make the call more readable 'testvercomp "1.23.1" "<" "1.28.1"' but i really don't know how/why it works how it is now)
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
    DB_TYPE=$(${GREPEXECUTABLE} -n "wgDBtype =" ${MEDIAWIKIDIR}/LocalSettings.php | $AWKEXECUTABLE -F '"' '{print $2}')
    echo "database type: ${DB_TYPE}"

    if [ "$DB_TYPE" = "mysql" ]; then
        local DB_SERVER=$(${GREPEXECUTABLE} "wgDBserver =" ${MEDIAWIKIDIR}/LocalSettings.php)
        local DB_SERVER=${DB_SERVER:15:-2}
        local DB_NAME=$(${GREPEXECUTABLE} "wgDBname =" ${MEDIAWIKIDIR}/LocalSettings.php)
        local DB_NAME=${DB_NAME:13:-2}
        local DB_USER=$(${GREPEXECUTABLE} "wgDBuser =" ${MEDIAWIKIDIR}/LocalSettings.php)
        local DB_USER=${DB_USER:13:-2}
        local DB_PW=$(${GREPEXECUTABLE} "wgDBpassword =" ${MEDIAWIKIDIR}/LocalSettings.php)
        local DB_PW=${DB_PW:17:-2}

        echo "backing up database to '${BACKUPDIR}/${DB_NAME}.sql'"
        ${MYSQLDUMPEXECUTABLE} -u ${DB_USER} -p${DB_PW} ${DB_NAME} > ${BACKUPDIR}/${DB_NAME}.sql
    else
        echo "database type is not 'mysql' (set BACKUP_MYSQL_DB to 'false' to continue without a backup created by this script) -> exiting"
        exit 1
    fi
}
# -FUNCTIONS

# +PROCESS
#check if "LocalSettings.php" exists
if [ ! -f ${MEDIAWIKIDIR}/LocalSettings.php ]; then
    echo "file 'LocalSettings.php' not found in directory '${MEDIAWIKIDIR}'!"
    exit 1
fi

#get mediawiki version from MEDIAWIKIDIR
INSTALLED_VERSION=$(${GREPEXECUTABLE} -n "wgVersion =" ${MEDIAWIKIDIR}/includes/DefaultSettings.php | ${AWKEXECUTABLE} -F "'" '{print $2}')
echo "currently installed version: ${INSTALLED_VERSION}"

LATEST_RELEASE=${INSTALLED_VERSION}

#get releases from https://github.com/wikimedia/mediawiki/releases.atom
LATEST_RELEASES=$(${WGETEXECUTABLE} -q -O- "https://github.com/wikimedia/mediawiki/releases.atom" | ${GREPEXECUTABLE} -o -P '<title>[^"]*' | ${SEDEXECUTABLE} "s/<title>//g" | ${SEDEXECUTABLE} "s/<\/title>//g")
for RELEASE in ${LATEST_RELEASES}; do
    if [[ "${RELEASE}" =~ [0-9] ]]; then
	#skip if release candidate
        if ! ${GREPEXECUTABLE} "\-rc\." <<< ${RELEASE} &>/dev/null; then
            if testvercomp ${RELEASE} "<" ${LATEST_RELEASE}; then
                LATEST_RELEASE=${RELEASE}
            fi
        fi
    fi
done

echo "latest release found: ${LATEST_RELEASE}"

#check if latest version is newer
if testvercomp ${LATEST_RELEASE} ">" ${INSTALLED_VERSION}; then
    echo "no newer version found on the interweb -> exiting"
    exit 1
fi

#if tmp directory exists delete it/append "_{int}"
if [ -d ${TMPDIR} ]; then
    COUNTER=1
    TMPBASEDIR=${TMPDIR}
    while [ -d ${TMPDIR} ]; do
        TMPDIR="${TMPBASEDIR}_${COUNTER}"
        COUNTER=$[COUNTER + 1]
    done
fi

#create tmp directory if not exists
if [ ! -d ${TMPDIR} ]; then
    ${MKDIREXECUTABLE} ${TMPDIR}
    echo "creating directory for temp: '${TMPDIR}'"
fi

#create backup directory if not exists
if [ ! -d ${BACKUPDIR} ]; then
    ${MKDIREXECUTABLE} ${BACKUPDIR}
    echo "creating directory for backup: '${BACKUPDIR}'"
fi

#create backup timestamp directory
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUPBASEDIR=${BACKUPDIR}
BACKUPDIR="${BACKUPDIR}/${TIMESTAMP}"
if [ ! -d ${BACKUPDIR} ]; then
    ${MKDIREXECUTABLE} ${BACKUPDIR}
    echo "creating directory for backup: '${BACKUPDIR}'"
fi

#backup mediawiki database
if ${BACKUP_MYSQL_DB}; then
    echo "trying to backup database"
    backupmysqldb
fi

#move $MEDIAWIKIDIR to $BACKUPDIR
echo "moving '${MEDIAWIKIDIR}' to '${BACKUPDIR}/${INSTALLED_VERSION}'"
${MKDIREXECUTABLE} ${BACKUPDIR}/${INSTALLED_VERSION}
mv ${MEDIAWIKIDIR}/* ${BACKUPDIR}/${INSTALLED_VERSION}

if [[ ${TAREXECUTABLE} ]]; then
	#download new mediawiki version
    VERSION=$(echo ${LATEST_RELEASE} | ${AWKEXECUTABLE} -F "." '{ print $1 "." $2 }')
    URL="https://releases.wikimedia.org/mediawiki/${VERSION}/mediawiki-${LATEST_RELEASE}.tar.gz"
    echo "downloading version '${LATEST_RELEASE}' from $URL"
	${WGETEXECUTABLE} ${URL} -O ${TMPDIR}/${LATEST_RELEASE}.tar.gz -o /dev/null

	#extract downloaded release
	echo "extracting '${TMPDIR}/${LATEST_RELEASE}.tar.gz'"
	pushd ${TMPDIR} &>/dev/null
	if ${TAREXECUTABLE} -tzf ${LATEST_RELEASE}.tar.gz &>/dev/null; then
	    ${TAREXECUTABLE} -xzf ${LATEST_RELEASE}.tar.gz
	    popd &>/dev/null
	else
	    popd &>/dev/null
	    echo "download (${TMPDIR}/${LATEST_RELEASE}.tar.gz) seems not to be a valid tar.gz file"
	    exit 1
	fi
else
    echo "cannot extract new release"
    exit 1
fi

#get extracted directory
NEW_RELEASE_DIRECTORY=$(ls -d ${TMPDIR}/*/)
if [[ ${NEW_RELEASE_DIRECTORY} ]]; then
	#move new version to mediawiki directory
	echo "updating installation with new files"
	mv ${NEW_RELEASE_DIRECTORY}/* ${MEDIAWIKIDIR}
fi

#copy LocalSettings.php to new version
echo "copying LocalSettings.php from previous version"
cp ${BACKUPDIR}/${INSTALLED_VERSION}/LocalSettings.php ${MEDIAWIKIDIR}/LocalSettings.php

#copy images from old installation to new version
echo "copying images from previous version"
cp -a ${BACKUPDIR}/${INSTALLED_VERSION}/images ${MEDIAWIKIDIR}

#copy skins from old installation to new version
echo "copying skins from previous version"
for SKINPATH in `ls -d ${BACKUPDIR}/${INSTALLED_VERSION}/skins/*/`; do
    SKINNAME=$(${BASENAMEEXECUTABLE} ${SKINPATH})
    if [ ! -d ${MEDIAWIKIDIR}/skins/${SKINNAME} ]; then
        cp -a ${SKINPATH} ${MEDIAWIKIDIR}/skins
    fi
done

#copy extensions from old installation if not existing in new version
echo "copying extensions from previous version"
for EXTENSIONPATH in `ls -d ${BACKUPDIR}/${INSTALLED_VERSION}/extensions/*/`; do
    EXTENSIONNAME=$(${BASENAMEEXECUTABLE} ${EXTENSIONPATH})
    if [ ! -d ${MEDIAWIKIDIR}/extensions/${EXTENSIONNAME} ]; then
        cp -a ${EXTENSIONPATH} ${MEDIAWIKIDIR}/extensions
    fi
done

#remove old backup directory
echo "removing old backups (keeping last 3)"
for OLDBACKUPDIR in `ls -t -d ${BACKUPBASEDIR}/*/ | ${GREPEXECUTABLE} -v "$(ls -t ${BACKUPBASEDIR}/ | ${HEADEXECUTABLE} -3)"`; do
    rm -r ${OLDBACKUPDIR}
done

#remove tmp directory
rm -r ${TMPDIR}

#TODO chown

#execute update script
${PHPEXECUTABLE} ${MEDIAWIKIDIR}/maintenance/run.php update.php
# -PROCESS
