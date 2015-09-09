platform_service cfengine3 stop
if [ -x /bin/systemctl ]; then
  # When using systemd, the services are split in two, and although both will
  # stop due to the command above, the web part may only do so after some
  # delay, which may cause problems later if the binaries are gone by the time
  # it tries to stop them.
  /bin/systemctl stop cfengine3-web
fi

case "`os_type`" in
  redhat)
    chkconfig --del cfengine3
    ;;
  debian)
    update-rc.d cfengine3 remove
    ;;
esac

#
#MAN PAGE RELATED
#
MAN_CONFIG=""
case "`package_type`" in
  rpm)
    if [ -f /etc/SuSE-release ];
    then
      # SuSE
      MAN_CONFIG="/etc/manpath.config"
    else
      # RH/CentOS
      MAN_CONFIG="/etc/man.config"
    fi
    ;;
  deb)
    MAN_CONFIG="/etc/manpath.config"
    ;;
  *)
    echo "Unknown manpath, should not happen!"
    ;;
esac

if [ -f "$MAN_CONFIG" ]; then
  grep -q cfengine "$MAN_CONFIG"
  if [ $? = "0" ]; then
    sed -i '/cfengine/d' "$MAN_CONFIG"
  fi
fi

#
# Clean lock files created by initscript, if any
#
for i in cf-execd cf-serverd cf-monitord cf-hub; do
  rm -f /var/lock/$i /var/lock/subsys/$i
done

exit 0