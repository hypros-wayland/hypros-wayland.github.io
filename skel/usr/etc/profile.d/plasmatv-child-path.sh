# Locked-down PATH for child-user-* accounts. rbash won't let the user
# change PATH themselves, so this is the only set of commands they can run.
case "$USER" in
  child-user-*)
    export PATH="/usr/local/lib/plasmatv-child-bin"
    ;;
esac
