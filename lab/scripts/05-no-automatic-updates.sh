#!/usr/bin/env bash
# No automatic updates in the lab VM. Ubuntu's defaults (the apt timers,
# unattended-upgrades, snap auto-refresh) restart services under a running lab: on
# 2 October 2026 an OpenSSL upgrade did that in an EasyMesh lab VM. A lab is updated by
# building it again. Run before the first apt-get; safe to run again.
set -euo pipefail
exec </dev/null

busy() {    # a unit that runs now
    case "$(systemctl is-active "$1" 2>/dev/null)" in
        active|activating) return 0 ;;
    esac
    return 1
}

systemctl mask --now apt-daily.timer apt-daily-upgrade.timer

# A run that has already started is left to finish: stopping apt half way leaves dpkg with
# packages half configured.
deadline=$((SECONDS + 900))
while busy apt-daily.service || busy apt-daily-upgrade.service; do
    [ "$SECONDS" -lt "$deadline" ] || { echo 'an automatic apt run did not finish in 15 minutes' >&2; exit 1; }
    sleep 2
done
systemctl mask apt-daily.service apt-daily-upgrade.service
systemctl disable --now unattended-upgrades.service 2>/dev/null || true

printf '%s\n' \
    'APT::Periodic::Update-Package-Lists "0";' \
    'APT::Periodic::Unattended-Upgrade "0";' \
    > /etc/apt/apt.conf.d/99-lab-no-automatic-updates

snap wait system seed.loaded
snap refresh --hold

install -d -m 0755 /var/lib/apps-lab
printf '%s\n' 'no-automatic-updates' > /var/lib/apps-lab/updates.status
