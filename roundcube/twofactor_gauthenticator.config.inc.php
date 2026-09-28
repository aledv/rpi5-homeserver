<?php
// If true, all users must log in with 2-step verification. They will receive an alert message and cannot skip the configuration.
// Default: Setting up 2FA is not necessary for enabled users (false)
$rcmail_config['force_enrollment_users'] = false;

// A Whitelist of IPs which are allowed to bypass the 2FA, CIDR format available.
// NOTE: We need to use .0 IP to define LAN because the class CIDR have a issue about that (we can't use 129.168.1.2/24, for example)
// NOTE2: To create a empty whitelist, make sure it looks like this: `$rcmail_config['whitelist'] = array();` <- There are NO QUOTES inside the parentheses.
// my_rpi_scripts: nessuna eccezione. Dietro NPM l'IP visto da Roundcube è quello del proxy, non del client:
// una whitelist della LAN farebbe saltare la 2FA a tutti.
$rcmail_config['whitelist'] = array();

// If true, there will be a checkbox in the the TOTP code prompting page. By ticking it, there will be no 2FA prompt for 30 days.
// Default: Allow saving devices (true)
$rcmail_config['allow_save_device_30days'] = true;

// If true, the entered TOTP code will appear as password in the webpage when prompting it. Otherwise, it'll shown as text.
// Default: Form field will be text (false)
$rcmail_config['twofactor_formfield_as_password'] = false;

// Users allowed to use plugin (IMPORTANT: other users DON'T have plugin activated). Regex is supported.
// my_rpi_scripts: tutte le caselle del dominio
$rcmail_config['users_allowed_2FA'] = array('.*@example\.com');

// If true, 2FA failure will be logged in file log_errors_2FA.txt under HOME_RC/logs/log_errors_2FA.txt.
// Suggested by @pngd (issue 131)
// Default: There will be no logs (false)
$rcmail_config['enable_fail_logs'] = false;

// If true, twofactor user preferences (secret and codes) will be encrypted with Roundcube's DES key.
$rcmail_config['twofactor_pref_encrypt'] = false;

// Incremental wait (seconds) applied after the N-th accumulated failed 2FA code (level N).
// Each value is clamped to >= 1; levels beyond the list use the LAST value.
// Default: [1, 2, 5, 20, 60, 300, 600]  (1s, 2s, 5s, 20s, 1 min, 5 min, 10 min)
$rcmail_config['twofactor_lockout_delays'] = array(1, 2, 5, 20, 60, 300, 600);

// Counter-expiry window (seconds) - resets the failure level. If the last failure is older
// than this window, the level resets to 0 before the next attempt is counted.
// Default: 900 (15 minutes)
$rcmail_config['twofactor_lockout'] = 900;

// List of trusted reverse-proxies (IPs or CIDR ranges) whose X-Forwarded-For header is
// honored for the IP whitelist decision and rate-limit key. When empty (default), header
// trust is disabled and only REMOTE_ADDR (the real TCP peer) is used. HTTP_CLIENT_IP is
// never used. Deployments whose clients connect through a proxy must add the proxy here
// or their whitelist stops matching.
// Default: array() (header trust disabled)
$rcmail_config['twofactor_trusted_proxies'] = array();
