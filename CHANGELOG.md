# Changelog

Notable and less notable changes. 

## [0.1.1]

- Now available in a repository for easy install and updating, https://github.com/gnyman/ha-addons

- Allow using luakit as browser. Luakit seems to be much lighter and faster while still being able to render the HA dashboard.

- Added option to keep the Chrome cache/user-profile in /data/. This should speed up chrome a bit and make "remember me" work.

- Divided HAVNC into two different lines. The old one and the new Here Be Dragons (-dragons for short). This is the "works on my machine" version. The normal one will be more of a LTS (long term support) version where I will do my best to avoid breakage. I promise I won't intentionally try to break things. The LTS version will eventually get the features from this version, and backported fixes. You can install and run both and switch between them as you wish.

## [0.0.9]

- Improve security (where improve actually means add some basic security so not everyone on the network can access your HA dashboard).
**Note**: Because a password is required the upgrade will end with a error telling you to check the supervisor logs. It's because there is no password set. After the upgrade, go to Configuration and add a password and then start the add-on again.

## [0.0.8]

- Initial public release.
