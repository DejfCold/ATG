# ATG - AppImage To Gnome
Monitors and (de)installs AppImage from Gnome desktop
(It might even work elsewhere, but I didn't try it - let me know!)

- There's no need for a root user!
- Runs as a user systemd service
- Monitors `~/apps` for new or removed AppImages

## Install
- download this repository
- set the execute bit on the `install.sh` script (`chmod +x install.sh` or via GUI)
- if `echo ${HOME}` doesn't look like `/home/[username]` where `[username]` is your username, skip to *Nonstandard user* section and then get back
- run the `install.sh`
- you can delete the downloaded folder now
- add an AppImage to the `~/apps/` directory, go to `Applications` and search for it. You should see it there now.

## Uninstall
If, for whatever reason, you want to uninstall this, run the following:
```sh
systemctl --user disable atg.path # disables the watch service
rm -f ~/.config/systemd/user/atg.path # removes the watch service
rm -f ~/.config/systemd/user/atg.service # removes the script runner
rm -f ~/.local/bin/atg.sh # removes the main script
```

## Nonstandard user
- run `echo ${HOME}` and copy it's output
- open `atg.path` and in `PathChanged=/home/%u/apps/` replace the `/home/%u` with the output from previous command
- return back to the *Install* section. (well, basically just run the install script)
