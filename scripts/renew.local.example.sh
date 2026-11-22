# Copy to scripts/renew.local.sh (not in git) and fill in.
DEVICE=00000000-0000000000000000          # your iPhone, from `xcrun devicectl list devices`

# Optional: a second free-Apple-ID app to keep alive on the same schedule.
# OTHER_INSTALL runs only when its signature has less than 3 days left; it must request fresh profiles itself.
# OTHER_NAME=MyApp
# OTHER_APP_ID=hu.yourname.myapp
# OTHER_INSTALL="RENEW=1 $HOME/Projects/MyApp/scripts/install.sh"
