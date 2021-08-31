#!/bin/bash
RED='\033[0;31m'
YELLOW='\033[0;33m'
GRAY='\033[1;30m'
NC='\033[0m'

WARN="[${YELLOW}WARN${NC}]:"
INFO="[${GRAY}INFO${NC}]:"
ERROR="[${RED}ERROR${NC}]:"

homedir=~/
appdir="${homedir}apps/"
installDir="${homedir}.local/share/applications/"

apps=($(tree $appdir -f -i | grep .AppImage))

echo -e "${INFO} Adding all AppImages"

for app in ${apps[@]}; do
	tmp="/tmp/ATG-$(uuidgen)/"
	currdir=$(pwd)

	echo -e "${INFO} Setting executable bit on ${app}"
	chmod +x ${app}

	mkdir -p ${tmp}
	cd ${tmp}
	echo -e "${INFO} Extracting ${app}"
	${app} --appimage-extract 1>/dev/null
	echo -e "${INFO} Extraction completed"
	cd ${tmp}/squashfs-root
	
	desktop_file=$(ls *.desktop)
	
	icon_line=$(cat ${desktop_file} | grep "Icon=")
	iconArr=(${icon_line//=/ })
	iconName=${iconArr[1]}
	iconFullName=$(ls | egrep "${iconName}\.(png|jpg|jpeg)")
	icon=$(readlink -f ${iconFullName} || echo ${iconFullName})
	iconSize=$(identify -format '%wx%h' ${icon})

	iconTargetDir=${homedir}.local/share/icons/hicolor/${iconSize}/apps/
	iconTargetFile=${iconTargetDir}${iconFullName}

	sed -i "/^Exec=/c\Exec=${app}" ${desktop_file}
	sed -i "/^Icon=/c\Icon=${iconTargetFile}" ${desktop_file}

	mkdir -p ${iconTargetDir}
	\cp -r ${desktop_file} ${installDir}
	\cp -r  ${icon} ${iconTargetFile}

	cd ${currdir}
	rm -rf ${tmp}
done

echo -e "${INFO} Added all AppImages"

echo -e "${INFO} Removing dead files"
IFS=$'\n'
installedApps=($(ls -d ${installDir}* | grep ".desktop"))
installedAppImages=()
for installedApp in "${installedApps[@]}"; do
	cat ${installedApp} | egrep -i "Exec=${appdir}.*\.AppImage" 1>/dev/null
	ret=$?
	if [ ${ret} -eq 0 ]; then
		installedAppImages+=(${installedApp})
	fi
done

usedLogos=()
uncheckedFilesToRemove=()
for installedAppImage in "${installedAppImages[@]}"; do
	IFS=' '
	execLine=$(cat ${installedAppImage} | grep "Exec=")
	execArr=(${execLine//=/ })
	execPath=${execArr[1]}

	logoLine=$(cat ${installedAppImage} | grep "Icon=")
	logoArr=(${logoLine//=/ })
	logoPath=${logoArr[1]}
	if [ -f "${execPath}" ]; then
		usedLogos+=(${logoPath})
	else
		uncheckedFilesToRemove+=(${installedAppImage})
		uncheckedFilesToRemove+=(${logoPath})
	fi

done

filesToRemove=()
for uncheckedFileToRemove in "${uncheckedFilesToRemove[@]}"; do
	IFS='|'
	if [[ ! " ${IFS}${usedLogos[*]}${IFS} " =~ " ${uncheckedFileToRemove} " ]]; then
		filesToRemove+=(${uncheckedFileToRemove})
	else 
		echo -e "${WARN} File "${uncheckedFileToRemove}" is referenced in existing Desktop file. Won\'t remove."
	fi
	unset IFS
done

for fileToRemove in "${filesToRemove[@]}"; do
	echo -e "${INFO} Removing file: ${fileToRemove}"
	rm -f  ${fileToRemove}
done
unset IFS

echo -e "${INFO} Removed dead files"
echo -e "${INFO} Finished"

