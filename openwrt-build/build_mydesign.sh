#!/bin/sh

func_build_adblock ()
{
	local NETWORK="$1"
	local ADBLOCK_VERSION="$2"
	local WDIR="buildadblock"
	local ADBLOCKURL="http://pgl.yoyo.org/as/serverlist.php?showintro=0;hostformat=hosts"

	[ -z "$NETWORK" ] && {
		echo "func_build_adblock <network> <version>"
		return 1
	}

	mkdir $WDIR
	cd $WDIR

	echo >"debian-binary" "2.0"

	cat >control <<EOF
Package: fff-adblock-list
Priority: optional
Version: $ADBLOCK_VERSION
Architecture: all
Maintainer: Bastian Bittorf <bittorf@bluebottle.com>
Section: networking
Description: adblock-domain-list, fetched @ $(date)
Source: $ADBLOCKURL
EOF

	mkdir etc
	wget -O /dev/null "$ADBLOCKURL" || WGETERR="$WGETERR $ADBLOCKURL"
	wget -O -	  "$ADBLOCKURL" | sed -n 's/127.0.0.1 \(.*\)/\1/p' >"etc/hosts.drop"
	ls -l etc/hosts.drop

	tar --owner=root --group=root -cvzf data.tar.gz etc/hosts.drop

	tar --owner=root --group=root -cvzf control.tar.gz ./control

	tar --owner=root --group=root -cvzf ../fff-adblock-list_${ADBLOCK_VERSION}_mipsel.ipk ./debian-binary ./control.tar.gz ./data.tar.gz

	cd ..
	rm -fR "$WDIR"
	ls -l fff-adblock-list_${ADBLOCK_VERSION}_mipsel.ipk

	echo "scp fff-adblock-list_${ADBLOCK_VERSION}_mipsel.ipk root@intercity-vpn.de:/var/www/networks/$NETWORK/packages/"
	while ! scp fff-adblock-list_${ADBLOCK_VERSION}_mipsel.ipk root@intercity-vpn.de:/var/www/networks/$NETWORK/packages/ ;do sleep 3;done

	rm fff-adblock-list_${ADBLOCK_VERSION}_mipsel.ipk
}

func_build_settings ()
{
	local NETWORK="$1"	# elephant | galerie | ...
	local VERSION="$2"	# 0.1 | 0.2 | ...

	local IPKG_NAME="mysettings"
	local IPKG_VERSION="${VERSION:-0.1}"
	local WDIR="build_settings_$NETWORK"
	local URL="http://www.datenkiste.org/cgi-bin/gitweb.cgi"
	local FILE="${IPKG_NAME}_${IPKG_VERSION}.ipk"

	mkdir $WDIR
	cd $WDIR

	local DIR="/home/$USER/Desktop/bittorf_wireless/kunden/galeriehotel,leipzigerhof/dokumentation"
	local CSV="345032-2009mai12-WLAN-Installation-Tabelle-Router_und_Standort.csv"

	cat >postinst <<EOF
#!/bin/sh

. /bin/needs vars_old base

[ "\$FFF_PLUS_VERSION" -lt 346172 ] && {
	ipkg remove horst libpcap libncurses freifunk-tcpdump
	wget -O /tmp/fw.tgz "http://intercity-vpn.de/firmware/broadcom/images/testing/tarball.tgz"
	cd /
	tar xzf /tmp/fw.tgz
	rm /tmp/fw.tgz
	/etc/init.d/S51crond_fff+ restart
}

. /tmp/NETPARAM
WIFIMAC="\$( ip -o link show dev \$WIFIDEV | sed -n 's/^.*ether \(..\):\(..\):\(..\):\(..\):\(..\):\(..\) .*/\1\2\3\4\5\6/p;q' )"
LANMAC="\$(  ip -o link show dev \$LANDEV  | sed -n 's/^.*ether \(..\):\(..\):\(..\):\(..\):\(..\):\(..\) .*/\1\2\3\4\5\6/p;q' )"

LINE="\$( grep ^"MAC=\"\$WIFIMAC\"" \$0 )"
[ -z "\$LINE" ] && LINE="\$( grep ^"MAC=\"\$LANMAC\"" \$0 )"
[ -n "\$LINE" ] && {
	echo
	echo "trying to apply '\$LINE'"
	eval \$LINE				# MAC|PROFILE|ESSID|HOST

	if [ "\$( nvram get wl0_ssid )" != "\$ESSID" -o "\$( nvram get fff_profile )" != "\$PROFILE" ]; then
		. /etc/functions_base_fff+ && func_need nvram log wifi
		. /etc/functions_profile_fff+
		. /etc/functions_profile_user_fff+
		. /etc/functions_profile_mac2profile_fff+

		MYLINE="\$LINE"
		func_nvset fff_profile  "\$PROFILE"
		func_profile_set_config "\$PROFILE"
		eval \$MYLINE

		func_nvset wan_hostname "\$HOST"
		func_nvset wl0_ssid "\$ESSID"
		func_nvset ff_nameservice
		func_nvset commit

		func_safe_reboot "new profile '\$PROFILE' enforced"
	else
		echo "already applied - ready"
	fi
}

exit

EOF
	sed -n 's/^[0-9]*,\("[0-9a-z]*"\),.*,.*,.*,.*,\(.*\),\(.*\),\(.*\),.*/MAC=\1;PROFILE=\2;ESSID=\3;HOST=\4;/p' "$DIR/$CSV" >>postinst

	cat postinst	# debug

	echo "2.0" >"debian-binary"

	cat >control <<EOF
Package: $IPKG_NAME
Version: $IPKG_VERSION
Priority: optional
Maintainer: Bastian Bittorf <technik@bittorf-wireless.de>
Section: net
Description: installs additional setting for '$NETWORK'
Source: $URL
EOF
	chmod 777 postinst

	tar --ignore-failed-read -czf ./data.tar.gz "" 2>/dev/null
	tar czf control.tar.gz ./control ./postinst
	tar czf "${IPKG_NAME}_${IPKG_VERSION}.ipk" ./debian-binary ./control.tar.gz ./data.tar.gz

	echo "scp "${IPKG_NAME}_${IPKG_VERSION}.ipk" root@intercity-vpn.de:/var/www/networks/$NETWORK/packages/"
	while ! scp "${IPKG_NAME}_${IPKG_VERSION}.ipk" root@intercity-vpn.de:/var/www/networks/$NETWORK/packages/ ;do sleep 3;done

	rm ./data.tar.gz ./debian-binary ./control.tar.gz control postinst
	cd ..
	rm -fR $WDIR
}

func_build_design ()
{
	local NETWORK="$1"		# elephant | galerie | ...
	local VERSION="${2:-0.1}"	# 0.1 | 0.2 | ...

	local IPKG_NAME="mydesign"
	local IPKG_VERSION="${VERSION:-0.1}"
	local WDIR="build_design_$NETWORK"
	local URL="http://www.datenkiste.org/cgi-bin/gitweb.cgi"
	local FILE="${IPKG_NAME}_${IPKG_VERSION}.ipk"
	local MYFILE
	local BW="$HOME/Desktop/bittorf_wireless"
	local BASE
	local BUILD_DATE="$( date "+%d-%b-%Y" )"

	mkdir -p "$WDIR"
	cd "$WDIR"
	mkdir -p "www/images"
	mkdir -p "www/cgi-bin"

	cp $HOME/Desktop/bittorf_wireless/kunden/Hotel_Elephant/grafiken/weblogin/button_login_de.gif  www/images/

	_copy_favicon_bittorf ()
	{
		local FAVDEST="www/favicon.ico"

		cp $HOME/Desktop/bittorf_wireless/vorlagen/grafiken/weblogin/favicon.ico $FAVDEST || echo "error favicon?!"
	}

	_copy_favicon_freifunk ()
	{
		wget -O www/favicon.ico "http://weimarnetz.de/favicon.ico" || echo "download favicon-fehler!"
	}

	_copy_flags ()		# fixme! jp=ja,dk=da
	{
		local DIR="$BW/vorlagen/grafiken/weblogin/flaggen"

		cp $DIR/flag_de.gif 				www/images/
		cp $DIR/flag_en.gif 				www/images/
		cp $DIR/flag_fr.gif				www/images/
		cp $DIR/flag_ru.gif				www/images/
		cp $DIR/flag_dk.gif				www/images/flag_da.gif
		cp $DIR/flag_jp_16x12_2colors_websafe.gif	www/images/flag_ja.gif
	}

	_copy_terms_of_use ()
	{
		local USERDIR="$1"
		local DATE="$( date "+%Y %b %d" | sed -e 's/ä/a/g' )"	# Maerz
		local SHORT_LANG FILE

		cp "$USERDIR/rules_meta_de.txt"	"www/images/weblogin_rules_de_meta"
		cp "$USERDIR/rules_meta_en.txt"	"www/images/weblogin_rules_en_meta"
		cp "$USERDIR/rules_meta_fr.txt"	"www/images/weblogin_rules_fr_meta"

		for LANG in de en fr; do {
			FILE="www/images/weblogin_rules_${LANG}_meta"
			grep -q ^"ERSTELLUNGSZEIT=" "$FILE" && {
				sed -i '/^ERSTELLUNGSZEIT=/d' "$FILE"
			}

			echo "ERSTELLUNGSZEIT='$DATE'" >>"$FILE"
		} done

		for LANG in deutsch-ISO_8859-1 english-ISO_8859-1 france-ISO_8859-15; do {
			SHORT_LANG="$( echo $LANG | cut -b1-2 )"
			FILE="$BW/vorlagen/nutzungsbedingungen/nutzungsbedingungen_$LANG.txt"
			DEST="www/images/weblogin_rules_${SHORT_LANG}.txt"

			sed "s/\${ERSTELLUNGSZEIT}/$DATE/g" "$FILE" >"$DEST"
		} done
	}

	die()
	{
		echo "fatal error"
		exit 1
	}

	case $NETWORK in
		example)
			continue
			# idea:
			# uses flags=standard favicon=standard usageterms=standard ...

			_copy_favicon_bittorf
			# /www/favicon.ico				# _copy_favicon
			
			_copy_flags
			# /www/images/weblogin/flag_[de|en|fr].gif	# _copy_flags	// Sprach-Symbole (deutsch koennte die Flagge ch|at|de sein?)
			# userdb_login_template.pdf

			# /www/images/button_login_de.gif		# Absendeknopf, farblich abgestimmt
			# /www/images/logo2.gif 			# Slogan-Grafik "Galerie Hotel Leipziger Hof \n Hier schlafen (surfen) sie mit einem Original"
			# /www/images/logo.gif				# Hauptlogo
			# /www/images/landing_page.txt			# http://url
			# /www/images/bgcolor.txt			# HTML z.b. '#FFD700' oder 'yellow'

			# /www/cgi-bin/userdata.txt			# default-passwoerter, format: "md5sum(${user}${pass}) kommentar"

			_copy_terms_of_use "$BASE"
			# /www/images/weblogin_rules_[de|en|fr_meta	# _copy_terms_of_use
			# /www/images/weblogin_rules_[de|en|fr].txt	# _copy_terms_of_use
		;;
		elephant)
			BASE="$BW/kunden/Hotel_Elephant/grafiken/weblogin"

			_copy_flags
			_copy_favicon_bittorf
			_copy_terms_of_use "$BASE"

			cp "$BASE/landing_page.txt"	  	www/images/
			cp "$BASE/logo.gif"			www/images/
			cp "$BASE/button_login_de.gif" 		www/images/button_login_de.gif
		;;
		galerie)
			BASE="$BW/kunden/galeriehotel,leipzigerhof/grafiken/weblogin"

			_copy_flags
			_copy_favicon_bittorf
			_copy_terms_of_use "$BASE"

			cp "$BASE/button_login_de.gif"	www/images/button_login_de.gif
			cp "$BASE/landing_page.txt" 	www/images/
			cp "$BASE/logo.gif"		www/images/
			cp "$BASE/logo2.gif"		www/images/
			cp "$BASE/bgcolor.txt"		www/images/
		;;
		zumnorde)
			BASE="$BW/kunden/Hotel_Zumnorde/grafiken/weblogin"

			_copy_flags
			_copy_favicon_bittorf
			_copy_terms_of_use "$BASE"

			cp "$BASE/button_login_de.gif"			www/images/button_login_de.gif
			cp "$BASE/landing_page.txt" 			www/images/
			#cp "$BASE/logo.gif"				www/images/
			cp "$BASE/logo-zumnorde_aus_eps_320px.gif"	www/images/logo.gif
		;;
		versilia|versiliawe|versiliaje)							# fixme! loginbutton?
			BASE="$BW/kunden/versilia/grafiken/weblogin"

			_copy_flags
			_copy_favicon_bittorf
			_copy_terms_of_use "$BASE"

			cp $BASE/logo.gif				www/images/
			cp $BASE/landing_page.txt			www/images/landing_page.txt
		;;
		ejbw)
			BASE="$BW/kunden/EJBW/grafiken/weblogin"

			_copy_flags
			_copy_favicon_bittorf
			_copy_terms_of_use "$BASE"

			cp $BASE/button_login_de.gif		www/images/
			cp $BASE/logo.gif			www/images/logo.gif
			cp $BASE/bgcolor.txt			www/images/bgcolor.txt
		;;
		rehungen)
			BASE="$BW/kunden/Breitband-Rehungen/grafiken/weblogin/"

			_copy_flags
			_copy_favicon_bittorf
			_copy_terms_of_use "$BASE"

			cp $BASE/button_login_de.gif				www/images/
			cp $BASE/rehungen_logo_transparent_32cols_220px.gif	www/images/logo.gif
			cp $BASE/bgcolor.txt					www/images/bgcolor.txt
		;;
		aschbach)
			BASE="$BW/kunden/cans-niko_jovicevic/Berghotel_Aschbach_WLAN-System/grafiken/weblogin"

			_copy_flags
			_copy_favicon_bittorf
			_copy_terms_of_use "$BASE"

			cp $BASE/loginbutton.gif					www/images/button_login_de.gif
			cp $BASE/logo-Aschbach_transparent_cropped_400px_16cols.gif	www/images/logo.gif
			cp $BASE/bgcolor.txt						www/images/bgcolor.txt
		;;
		abtpark)
			BASE="$BW/kunden/Abtnaundorfer_Park/grafiken/weblogin"

			_copy_flags
			_copy_favicon_bittorf
			_copy_terms_of_use "$BASE"

			cp "$BASE/button_login_de.gif"			www/images/button_login_de.gif
			cp "$BASE/logo.gif"				www/images/logo.gif
			cp "$BASE/bgcolor.txt"				www/images/bgcolor.txt
			cp "$BASE/font_face.txt"			www/images/font_face.txt
			cp "$BASE/font_color.txt"			www/images/font_color.txt
		;;
		dummy)
			BASE="$BW/vorlagen/weblogin_design/weblogin"

			_copy_flags
			_copy_favicon_bittorf
			_copy_terms_of_use "$BASE"

			cp "$BASE/button_login_de.gif"			www/images/button_login_de.gif
			cp "$BASE/logo.gif"				www/images/logo.gif
			cp "$BASE/bgcolor.txt"				www/images/bgcolor.txt
			cp "$BASE/font_face.txt"			www/images/font_face.txt
			cp "$BASE/font_color.txt"			www/images/font_color.txt
		;;
		schoeneck)
			BASE="$BW/kunden/IFA Schöneck/grafiken/weblogin"

			_copy_flags
			_copy_favicon_bittorf
			_copy_terms_of_use "$BASE"

			cp "$BASE/button_login_de.gif"			www/images/button_login_de.gif
			cp "$BASE/logo.gif"				www/images/logo.gif
			cp "$BASE/bgcolor.txt"				www/images/bgcolor.txt
			cp "$BASE/font_face.txt"			www/images/font_face.txt
			cp "$BASE/font_color.txt"			www/images/font_color.txt
		;;
		dhsylt)
			BASE="$BW/kunden/dorfhotel_sylt/grafiken/weblogin"

			_copy_flags
			_copy_favicon_bittorf
			_copy_terms_of_use "$BASE"

			cp "$BASE/button_login_de.gif"			www/images/button_login_de.gif
			cp "$BASE/generic-dorfhotel.gif"		www/images/logo.gif
			cp "$BASE/bgcolor.txt"				www/images/bgcolor.txt
			cp "$BASE/font_face.txt"			www/images/font_face.txt
			cp "$BASE/font_color.txt"			www/images/font_color.txt
		;;
		xoai)
			BASE="$BW/kunden/hotel_xoai_vietnam/grafiken/weblogin"

			_copy_flags
			_copy_favicon_bittorf
			_copy_terms_of_use "$BASE"

			cp "$BASE/button_login.gif"			www/images/button_login_de.gif
			cp "$BASE/logo.gif"				www/images/logo.gif
			cp "$BASE/bgcolor.txt"				www/images/bgcolor.txt
			cp "$BASE/font_face.txt"			www/images/font_face.txt
			cp "$BASE/font_color.txt"			www/images/font_color.txt
		;;
		ibfleesensee)
			BASE="$BW/kunden/tui-iberotel_fleesensee/grafiken/weblogin"

			_copy_flags
			_copy_favicon_bittorf
			_copy_terms_of_use "$BASE"

			cp "$BASE/button_login_de.gif"			www/images/button_login_de.gif
			cp "$BASE/logo.gif"				www/images/logo.gif
			cp "$BASE/bgcolor.txt"				www/images/bgcolor.txt
			cp "$BASE/font_face.txt"			www/images/font_face.txt
			cp "$BASE/font_color.txt"			www/images/font_color.txt
		;;
		dhfleesensee)
			BASE="$BW/kunden/Dorfhotel Fleesensee/grafiken/weblogin"

			_copy_flags
			_copy_favicon_bittorf
			_copy_terms_of_use "$BASE"

			cp "$BASE/button_login_de.gif"			www/images/button_login_de.gif
			cp "$BASE/logo_dorfhotel_fleesensee.gif"	www/images/logo.gif
			cp "$BASE/bgcolor.txt"				www/images/bgcolor.txt
			cp "$BASE/font_face.txt"			www/images/font_face.txt
			cp "$BASE/font_color.txt"			www/images/font_color.txt
		;;
		fparkssee)
			BASE="$BW/kunden/ferienpark_scharmuetzelsee/grafiken/weblogin"

			_copy_flags
			_copy_favicon_bittorf
			_copy_terms_of_use "$BASE"

			cp "$BASE/loginbutton.gif"			www/images/button_login_de.gif
			cp "$BASE/logo.gif"				www/images/logo.gif
			cp "$BASE/bgcolor.txt"				www/images/bgcolor.txt
		;;
		olympia)
			BASE="$BW/kunden/cans-niko_jovicevic/Hotel-Olympia_Muenchen/grafiken/weblogin"

			_copy_flags
			_copy_favicon_bittorf
			_copy_terms_of_use "$BASE"

			cp "$BASE/button_login_de.gif"		www/images/button_login_de.gif
			cp "$BASE/olympia-crop.gif"		www/images/logo2.gif
			cp "$BASE/balken.gif"			www/images/logo.gif
			cp "$BASE/bgcolor.txt"			www/images/bgcolor.txt
			cp "$BASE/font_face.txt"		www/images/font_face.txt
			cp "$BASE/font_color.txt"		www/images/font_color.txt
		;;
		spbansin)
			BASE="$BW/Akquise/Angebote_Ferienparks/Bansin/Seepark Bansin/grafiken/weblogin"

			_copy_flags
			_copy_favicon_bittorf
			_copy_terms_of_use "$BASE"

			cp "$BASE/button_login_de.gif"						www/images/button_login_de.gif
			cp "$BASE/logo_seepark_bansin_crop_190px_alpha.gif"			www/images/logo.gif
			cp "$BASE/font_face.txt"						www/images/font_face.txt
			cp "$BASE/font_color.txt"						www/images/font_color.txt
		;;
		itzehoe)
			BASE="$BW/kunden/stadtwerke_itzehoe/grafiken/weblogin"

			_copy_flags
			_copy_favicon_bittorf
			_copy_terms_of_use "$BASE"

			cp $BASE/loginbutton_orangerot.gif					www/images/button_login_de.gif
			cp $BASE/einzellogo_01_crop_16cols.gif					www/images/logo.gif
			cp $BASE/font_face.txt							www/images/font_face.txt
			cp $BASE/font_color.txt							www/images/font_color.txt
		;;
		tkolleg)
			BASE="$BW/kunden/Thueringenkolleg/grafiken/weblogin"

			_copy_flags
			_copy_favicon_bittorf
			_copy_terms_of_use "$BASE"

			cp $BASE/loginbutton.gif						www/images/button_login_de.gif
			cp $BASE/tkolleg-merged-cropped.gif					www/images/logo.gif
			cp $BASE/bgcolor.txt							www/images/bgcolor.txt
			cp $BASE/font_face.txt							www/images/font_face.txt
			cp $BASE/font_color.txt							www/images/font_color.txt
		;;
		hotello-*)
			case "$NETWORK" in
				*K80)
					BASE="$BW/kunden/cans-niko_jovicevic/Hotello_K80-WLAN-System/grafiken/weblogin"
				;;
				*B01)
					BASE="$BW/kunden/cans-niko_jovicevic/Hotello_B01-WLAN-System/grafiken/weblogin"
				;;
				*F22)
					BASE="$BW/kunden/cans-niko_jovicevic/Hotello_F22-WLAN-System/grafiken/weblogin"
				;;
				*H09)
					BASE="$BW/kunden/cans-niko_jovicevic/Hotello_H09-WLAN-System/grafiken/weblogin"
				;;
				*)
					BASE="$BW/kunden/cans-niko_jovicevic/Hotello_H09-WLAN-System/grafiken/weblogin"
				;;
			esac

			_copy_flags
			_copy_favicon_bittorf
			_copy_terms_of_use "$BASE"

			cp $BASE/button_login_de2_grau.gif					www/images/button_login_de.gif
			cp $BASE/Logo_Hotello_Gruppe_Blau_negativ_PANTONE_crop_251px.gif	www/images/logo.gif
			cp $BASE/bgcolor-dunkelblau.txt						www/images/bgcolor.txt
			cp $BASE/font_face.txt							www/images/font_face.txt
			cp $BASE/font_color.txt							www/images/font_color.txt
		;;
		limona)
			BASE="$BW/kunden/limona_weimar/grafiken/weblogin"

			_copy_flags
			_copy_favicon_bittorf
			_copy_terms_of_use "$BASE"

			cp $BASE/loginbutton.gif						www/images/button_login_de.gif
			cp $BASE/logo_16cols.gif						www/images/logo.gif
#			cp $BASE/font_face.txt							www/images/font_face.txt
#			cp $BASE/font_color.txt							www/images/font_color.txt
		;;
		shankar)
			BASE="$BW/kunden/shankar_peerthy/africa/grafiken/weblogin"

			_copy_flags
			_copy_favicon_bittorf
			_copy_terms_of_use "$BASE"

			cp $BASE/adtag.js							www/advertisement.js
			cp $BASE/button_login_de.gif						www/images/button_login_de.gif
			cp $BASE/WiCloud_switzerlang_16cols.gif					www/images/logo.gif
			cp $BASE/font_face.txt							www/images/font_face.txt
			cp $BASE/font_color.txt							www/images/font_color.txt
		;;
		cupandcoffee)
			BASE="$BW/kunden/cup_und_coffee/grafiken/weblogin"

			_copy_flags
			_copy_favicon_bittorf
			_copy_terms_of_use "$BASE"

			cp $BASE/loginbutton.gif						www/images/button_login_de.gif
			cp $BASE/coffee_small.gif						www/images/logo.gif
			cp $BASE/font_face.txt							www/images/font_face.txt
			cp $BASE/font_color.txt							www/images/font_color.txt
		;;
		preskil)
			BASE="$BW/kunden/shankar_peerthy/mauritius/preskil/grafiken/weblogin"

			_copy_flags
			_copy_favicon_bittorf
			_copy_terms_of_use "$BASE"

			cp $BASE/loginbutton_orangerot.gif					www/images/button_login_de.gif
			cp $BASE/logo.gif							www/images/logo.gif
			cp $BASE/logo3.gif							www/images/logo3.gif
			cp $BASE/font_face.txt							www/images/font_face.txt
			cp $BASE/font_color.txt							www/images/font_color.txt
		;;
		satama)
			BASE="$BW/kunden/SATAMA/grafiken/weblogin"

			_copy_flags
			_copy_favicon_bittorf
			_copy_terms_of_use "$BASE"

			cp $BASE/loginbutton.gif					www/images/button_login_de.gif
			cp $BASE/satama-logo_crop_217px.gif				www/images/logo.gif
			cp $BASE/bgcolor.txt						www/images/bgcolor.txt
		;;
		castelfalfi)
			BASE="$BW/kunden/castelfalfi/grafiken/weblogin"

			_copy_flags
			_copy_favicon_bittorf
			_copy_terms_of_use "$BASE"

			cp $BASE/button_login_de.gif	www/images/
			cp $BASE/logo.gif		www/images/logo.gif
			cp "$BASE/bgcolor.txt"		www/images/bgcolor.txt
			cp "$BASE/font_face.txt"	www/images/font_face.txt
			cp "$BASE/font_color.txt"	www/images/font_color.txt
		;;
		marinabh)
			BASE="$BW/kunden/marina-boltenhagen/grafiken/weblogin"

			_copy_flags
			_copy_favicon_bittorf
			_copy_terms_of_use "$BASE"

			cp $BASE/button_login_de.gif	www/images/
			cp $BASE/logo.gif		www/images/logo.gif
			cp "$BASE/bgcolor.txt"		www/images/bgcolor.txt
			cp "$BASE/font_face.txt"	www/images/font_face.txt
			cp "$BASE/font_color.txt"	www/images/font_color.txt
		;;
		boltenhagendh)
			BASE="$BW/kunden/tui-boltenhagen/dorfhotel/grafiken/weblogin"

			_copy_flags
			_copy_favicon_bittorf
			_copy_terms_of_use "$BASE"

			cp $BASE/button_login_de.gif	www/images/
			cp $BASE/logo.gif		www/images/logo.gif
			cp "$BASE/bgcolor.txt"		www/images/bgcolor.txt
			cp "$BASE/font_face.txt"	www/images/font_face.txt
			cp "$BASE/font_color.txt"	www/images/font_color.txt
		;;
		giancarlo)
			BASE="$BW/kunden/Giancarlo/grafiken/weblogin"

			_copy_flags
			_copy_favicon_bittorf
			_copy_terms_of_use "$BASE"

			cp $BASE/button_login_de.gif	www/images/
			cp $BASE/logo.gif		www/images/logo.gif
			cp "$BASE/bgcolor.txt"		www/images/bgcolor.txt
			cp "$BASE/font_face.txt"	www/images/font_face.txt
			cp "$BASE/font_color.txt"	www/images/font_color.txt
		;;
		palais)
			BASE="$BW/kunden/palais_altstadt/grafiken/weblogin"

			_copy_flags
			_copy_favicon_bittorf
			_copy_terms_of_use "$BASE"

			cp $BASE/button_login_de.gif	www/images/
			cp $BASE/logo.gif		www/images/logo.gif
			cp "$BASE/bgcolor.txt"		www/images/bgcolor.txt
			cp "$BASE/font_face.txt"	www/images/font_face.txt
			cp "$BASE/font_color.txt"	www/images/font_color.txt
		;;
		malchowit)
			BASE="$BW/kunden/malchowit/wlan-installationen/zimmer_mellentin/grafiken/weblogin"

			_copy_flags
			_copy_favicon_bittorf
			_copy_terms_of_use "$BASE"

			cp $BASE/button_login_de.gif	www/images/
			cp $BASE/logo.gif		www/images/logo.gif
			cp "$BASE/bgcolor.txt"		www/images/bgcolor.txt
			cp "$BASE/font_face.txt"	www/images/font_face.txt
			cp "$BASE/font_color.txt"	www/images/font_color.txt
		;;
		leonardo)
			BASE="$BW/kunden/Leonardo_Leipzig/grafiken/weblogin"

			_copy_flags
			_copy_favicon_bittorf
			_copy_terms_of_use "$BASE"

			cp $BASE/button_login_de.gif			www/images/
			cp $BASE/logo_leonardo_Symbol_16cols.gif	www/images/logo.gif
		;;
		lisztwe)
			BASE="$BW/kunden/Messepark Leipzig Markkleeberg/Hotel_Liszt/grafiken/weblogin"

			_copy_flags
			_copy_favicon_bittorf
			_copy_terms_of_use "$BASE"

			cp "$BASE/logo.gif"		www/images/logo.gif
			cp "$BASE/loginbutton.gif"	www/images/button_login_de.gif
			cp "$BASE/landing_page.txt"	www/images/
		;;
		adagio)
			BASE="$BW/kunden/Messepark Leipzig Markkleeberg/Hotel_Adagio/grafiken/weblogin"
		
			_copy_flags
			_copy_favicon_bittorf
			_copy_terms_of_use "$BASE"

			cp "$BASE/logo.gif"		www/images/logo.gif
			cp "$BASE/loginbutton.gif"	www/images/button_login_de.gif
			cp "$BASE/landing_page.txt"	www/images
			cp "$BASE/bgcolor.txt"		www/images
		;;
		berlinle)
			BASE="$BW/kunden/hotel_berlin_in_leipzig/grafiken/weblogin"
		
			_copy_flags
			_copy_favicon_bittorf
			_copy_terms_of_use "$BASE"

			cp "$BASE/logo.gif"		www/images/logo.gif
			cp "$BASE/loginbutton.gif"	www/images/button_login_de.gif
			cp "$BASE/landing_page.txt"	www/images
			cp "$BASE/bgcolor.txt"		www/images
		;;
		marinapark)
			BASE="$BW/kunden/dancenter_marinapark/grafiken/weblogin"

			_copy_flags
			_copy_favicon_bittorf
			_copy_terms_of_use "$BASE"

			cp "$BASE/DanCenter-Logo_GIF_transparent_crop_220px_8cols.GIF"	www/images/logo.gif
			cp "$BASE/loginbutton.gif"					www/images/button_login_de.gif
			cp "$BASE/landing_page.txt"					www/images
			cp "$BASE/bgcolor.txt"						www/images
		;;
		vivaldi)
			BASE="$BW/kunden/vivaldi hotel/grafiken/weblogin"

			_copy_flags
			_copy_favicon_bittorf
			_copy_terms_of_use "$BASE"

			cp "$BASE/logo_alt.gif"					www/images/logo.gif
#			cp "$BASE/logo-vivaldi_hotel_leipzig_optimized.gif"	www/images/logo.gif
			cp "$BASE/loginbutton.gif"				www/images/button_login_de.gif
			cp "$BASE/landing_page.txt"				www/images
			cp "$BASE/bgcolor.txt"					www/images
		;;
		apphalle)
			BASE="$BW/kunden/Messepark Leipzig Markkleeberg/AppartementhausHalle/grafiken/weblogin"
		
			_copy_flags
			_copy_favicon_bittorf
			_copy_terms_of_use "$BASE"

			cp "$BASE/logo.gif"		www/images/logo.gif
			cp "$BASE/loginbutton.gif"	www/images/button_login_de.gif
			cp "$BASE/landing_page.txt"	www/images/
		;;
		sachsenhausen)
			BASE="$BW/kunden/elektro-schaefer/breitband_sachsenhausen/grafiken/weblogin"

			_copy_flags
			_copy_favicon_bittorf

			cp "$BASE/logo.gif"				www/images/logo.gif
			cp "$BASE/loginbutton.gif"			www/images/button_login_de.gif
			cp "$BASE/landing_page.txt"			www/images/
			cp "$BASE/rules_meta_de.txt"			www/images/weblogin_rules_de_meta
			cp "$BASE/rules_meta_en.txt"			www/images/weblogin_rules_en_meta
			cp "$BASE/rules_meta_fr.txt"			www/images/weblogin_rules_fr_meta

			cp "$BW/vorlagen/nutzungsbedingungen/nutzungsbedingungen_deutsch-ISO_8859-1.txt"	www/images/weblogin_rules_de.txt
			cp "$BW/vorlagen/nutzungsbedingungen/nutzungsbedingungen_english-ISO_8859-1.txt"	www/images/weblogin_rules_en.txt
			cp "$BW/vorlagen/nutzungsbedingungen/nutzungsbedingungen_france-ISO_8859-15.txt"	www/images/weblogin_rules_fr.txt
		;;
		paltstadt)
			BASE="$BW/kunden/Elektro-Steinmetz/Pension_Altstadt/weblogin"

			_copy_flags
			_copy_favicon_bittorf
			_copy_terms_of_use "$BASE"

			cp "$BASE/logo.gif"			www/images/logo.gif
			cp "$BASE/loginbutton.gif"		www/images/button_login_de.gif
			cp "$BASE/bgcolor.txt"			www/images/
		;;
		liszt28)
##			BASE="$BW/kunden/liszt28/weblogin"
#			BASE="$BW/kunden/liszt28/weblogin/lalaba"
#			BASE="$BW/kunden/liszt28/weblogin/barcamp2012"
			BASE="$BW/kunden/liszt28/weblogin/schlachthof"

			_copy_flags			|| die
			_copy_favicon_bittorf		|| die
			_copy_terms_of_use "$BASE"	|| die

#			wget -O www/images/logo.gif http://heartbeat.piratenfreifunk.de/images/logos_merged.png
#			cp "$BASE/foto-liszt28-vorderansicht.gif"	www/images/logo.gif
##			cp "$BASE/franz_liszt-partitur.gif"		www/images/logo.gif
##			cp "$BASE/button_login_de.gif"			www/images/button_login_de.gif
##			cp "$BASE/landing_page.txt"			www/images/
##			cp "$BASE/bgcolor.txt"				www/images/
#			echo "http://google.de/search?q=piraten+freifunk" >www/images/landing_page.txt

#			cp "$BASE/background_body_crop_400px.gif"	www/images/logo.gif
			cp "$BASE/image-schlacht001-schrift-440px-16cols.gif"	www/images/logo.gif	|| die
#			cp "$BASE/logo.gif"				www/images/logo.gif
			cp "$BASE/loginbutton.gif"			www/images/button_login_de.gif	|| die
			cp "$BASE/bgcolor.txt"				www/images/			|| die
#			cp "$BASE/landing_page.txt"			www/images/
#			cp "$BASE/font_face.txt"			www/images/
#			cp "$BASE/font_color.txt"			www/images/
		;;
		monami)
			BASE="$BW/kunden/monami/grafiken/weblogin"

			_copy_flags
			_copy_favicon_bittorf
			_copy_terms_of_use "$BASE"

			cp "$BASE/monami-haus-64col.gif"	www/images/logo.gif
			cp "$BASE/button_login_de.gif"		www/images/button_login_de.gif
			cp "$BASE/landing_page.txt"		www/images/
		;;
		ffweimar)

			BASE="$BW/kunden/weimarnetz/grafiken/weblogin"

			_copy_flags											# really?
			_copy_favicon_freifunk

#			cp "$BASE/weimarnetz-mittelalter.jpg"			www/images/intro.jpg
			cp "$BASE/schaeuble/head.gif"				www/
			cp "$BASE/schaeuble/watching.js"			www/
#			cp "$BASE/logocontest-itten-brahm17-transparent.gif"	www/images/logo.gif			# really?
			cp "$BASE/ulis_logo.gif"				www/images/logo.gif
			cp "$BASE/button_login_de.gif"				www/images/button_login_de.gif		# really?


			# http://wireless.subsignal.org/index.php?title=Bild:Falke16.jpg
			# http://wireless.subsignal.org/images/d/d4/Die_suche_klein.JPG
			# http://wireless.subsignal.org/images/c/c7/Freifunkwiese_klein.jpg
			# http://wireless.subsignal.org/images/b/b6/Social_event.jpg
			# http://weimarnetz.de/freifunk/bilder/wirelessafrica.jpg
			# http://weimarnetz.de/freifunk/bilder/Node354_klein_schrift.jpg
		;;
	esac

	chmod -R 777 www	# rw-r-r

	ls -lR www/

	[ -e www/cgi-bin/userdata.txt ] && {
		echo
		echo "Userdata:"
		cat www/cgi-bin/userdata.txt
	}

	[ -e www/images/landing_page.txt ] && {
		echo
		echo "Landing Page: '$( cat www/images/landing_page.txt )'"
	}

	echo
	for MYFILE in $( find www/ -type f ); do {
		file -i "$MYFILE" | grep -q ": image/" && {
			echo "$( file -b "$MYFILE" )	$MYFILE"
		}
	} done
	echo

	[ -e 'www/images/button_login_de.gif' ] || {
		echo
		echo "ERROR - not found: www/images/button_login_de.gif"
		echo
	}

        echo "2.0" >"debian-binary"

        cat >control <<EOF
Package: $IPKG_NAME
Priority: optional
Version: $IPKG_VERSION
Maintainer: Bastian Bittorf <technik@bittorf-wireless.de>
Section: www
Description: installs all specific design elements for network '$NETWORK'
Architecture: all
Source: $URL
EOF

        tar --owner=root --group=root -cvzf control.tar.gz ./control
	tar --owner=root --group=root -cvzf data.tar.gz $( test -d www && echo www ) $( test -d etc && echo etc )
	tar --owner=root --group=root -cvzf $FILE ./debian-binary ./control.tar.gz ./data.tar.gz

	echo
	echo "scp $FILE root@intercity-vpn.de:/var/www/networks/$NETWORK/packages/"
	echo
	echo "# install with 'ipkg install http://intercity-vpn.de/networks/$NETWORK/packages/$FILE"
	echo "# press enter/return to continue, CTRL+C to abort"
	echo "# working directory: $( pwd )"

	read NOP
	while ! scp $FILE root@intercity-vpn.de:/var/www/networks/$NETWORK/packages/ ;do sleep 3;done
	
	cd ..
	rm -fR $WDIR
}

case "$1" in
	adblock)
		func_build_adblock $2 $3		# ffsundi
	;;
	design)
		[ -z "$2" ] && {
			echo "Usage: $0 design lisztwe (0.2|?)"
			exit 1
		}

		[ "$3" = "?" ] && {
			wget -qO - "http://intercity-vpn.de/networks/$2/packages/Packages" | while read LINE; do {

				case "$LINE" in
					*mydesign*) DIRTY=1 ;;
				esac

				case "$DIRTY" in
					1)
						case "$LINE" in
							Version*)
								echo $LINE
								exit 1
							;;
						esac
					;;
				esac

			} done

			exit 1
		}

		func_build_design $2 $3		# elephant 0.2
	;;
	settings)
		func_build_settings $2 $3	# galerie 0.1
	;;
esac