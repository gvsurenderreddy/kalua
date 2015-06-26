#!/bin/sh

NETWORK="$1"
VERSION="$2"

[ -z "$NETWORK" ] && {
	echo "Usage: $0 <network> <version>"
	exit 1
}

DIR_DATA_SOURCE="/var/www/networks/$NETWORK/settings"

case "$VERSION" in
	"")
		VERSION="0.1"
	;;
esac

WDIR="/tmp/${NETWORK}-${VERSION}"
mkdir -p "$WDIR"
cd "$WDIR"

TAB="	"

generate_script()
{
	cat <<EOF
#!/bin/sh
. /tmp/loader

apply_settings()
{
	[ -e "/sbin/uci" ] || return 1

	local mac="\$( _sanitizer do "\$( _net dev2mac \$WIFIDEV )" hex lowercase )"

	hostname()
	{
		local wish="\$1"
		local now="\$( uci get system.@system[0].hostname )"

		[ "\$now" = "\$wish" ] || {
			_log do set_hostname daemon info "setting new hostname '\$wish' (was: '\$now')"
			uci set system.@system[0].hostname="\$wish"
			uci commit system
			echo "\$wish" >"/proc/sys/kernel/hostname"
		}
	}

	essid()
	{
		local wish="\$1"
		local now="\$( uci get wireless.@wifi-iface[0].ssid )"

		[ "\$now" = "\$wish" ] || {
			_log do set_ssid daemon info "setting new SSID '\$wish' (was: '\$now')"
			uci set wireless.@wifi-iface[0].ssid="\$wish"
			uci commit wireless
			wifi
		}
	}

	case "\$mac" in
EOF

	COUNTER=0	# count AP's

	for FILE in $DIR_DATA_SOURCE/* ; do {

		MAC="$( basename "$FILE" | cut -d'.' -f1 )"

		echo "${TAB}${TAB}${MAC})"

		[ -e "$DIR_DATA_SOURCE/$MAC.hostname" ] && {
			HOSTNAME=
			read HOSTNAME <"$DIR_DATA_SOURCE/$MAC.hostname"
			[ -n "$HOSTNAME" ] && {
				logger -s "$MAC.hostname -> $HOSTNAME"
				echo "${TAB}${TAB}${TAB}hostname '$HOSTNAME'"
			}
		}

		case "$HOSTNAME" in
			*"-AP")
				COUNTER=$(( COUNTER + 1 ))
				ESSID="IFA $COUNTER"
				logger -s "$MAC.essid -> $ESSID (autogenerated)"
				echo "${TAB}${TAB}${TAB}essid '$ESSID'"
			;;
		esac

#		[ -e "$DIR_DATA_SOURCE/$MAC.essid" ] && {
#			ESSID=
#			read ESSID <"$DIR_DATA_SOURCE/$MAC.essid"
#			[ -n "$ESSID" ] && {
#				logger -s "$MAC.essid -> $ESSID"
#				echo "${TAB}${TAB}${TAB}essid '$ESSID'"
#			}
#		}

		echo "${TAB}${TAB};;"
	} done

	cat <<EOF
	esac
}

apply_settings
EOF
}

generate_script >"postinst"
chmod 777 "postinst"
cp postinst /tmp/postinst

echo "2.0" >"debian-binary"

PKG_NAME="mysettings"
PKG_VERSION="${VERSION}"

cat >control <<EOF
Package: $PKG_NAME
Version: $PKG_VERSION
Architecture: all
Priority: optional
Maintainer: Bastian Bittorf <technik@bittorf-wireless.de>
Section: net
Description: set specific params for network '$NETWORK', e.g. ESSID or HOSTNAME
Source: $DIR_DATA_SOURCE/
EOF

tar --ignore-failed-read -czf ./data.tar.gz "" 2>/dev/null
tar czf control.tar.gz ./control ./postinst
tar czf "${PKG_NAME}_${PKG_VERSION}.ipk" ./debian-binary ./control.tar.gz ./data.tar.gz

mv "${PKG_NAME}_${PKG_VERSION}.ipk" /var/www/networks/$NETWORK/packages
cd /var/www/networks/$NETWORK/packages
/var/www/scripts/gen_package_list.sh start
rm -fR "$WDIR"

