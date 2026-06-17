Nginx container build with modsecurity

```bash
cp nginx-build.container nginx-build.timer ~/.config/containers/systemd/
cp nginx-build.timer ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now nginx-build.timer
systemctl --user start nginx-build.service
```

Make a secret named CODEBERG_PACKAGE_RW

Set environment
