## Home Assistant Dashboard through VNC

_Note_: This is a pre-release, it mostly works on my iPad2, most of the time, but unless you want to fiddle I'd wait a bit.


Simple add-on which allows you to view and interact with a dashboard (or any other webpage) through a modern chromium instance inside a noVNC webpage.

Very useful in case your browser don't support all the newfangled webstuff but enough to work with older versions of noVNC.

For example the iPad2.

## Usage
Install from my [ha-addon repository](https://github.com/gnyman/ha-addons) or manually. Note that this DRAGON build is quite big and on a PI it will take *a long time* to download and extract the first time. Have patience, enjoy a cup of hot beverage.

After you have installed it, check the configuration page. Read the descriptions.

Then visit http://homeassistant.local:8080?password=NOVNCPASSWORD from the same network where your HA runs. 

If everything worked, you will see a gray NOVNC page and then it will load the dashboard. If something went wrong, see the log and try to figure out what went wrong. You can report issues either in the [Home Assistant forum](https://community.home-assistant.io/t/havnc-add-on-access-your-dashboards-on-older-unsupported-devices/859798/48) or as [github issues](https://github.com/gnyman/havnc/issues). 

## Remembering browser logins

Enable `persist_data` in the add-on configuration to keep browser cookies, local
storage, and profile data across add-on restarts and upgrades. When it is
disabled (the default), browser data is intentionally temporary and you may
need to log in again after a restart. The persistent profile is stored in the
add-on's `/data/browser-data` directory.

## Tips
[Kiosk-mode](https://github.com/NemesisRE/kiosk-mode) is really useful for a cleaner look.

[ha-lcars](https://github.com/th3jesta/ha-lcars) for the one true interface (as seen in my example photo).
