# Required production event

Collect one complete Home Assistant event containing `Login attempt or request
with invalid authentication` whose logger is not
`homeassistant.components.http.ban`. Preserve the syslog/journald header, logger
name, source-host text, parenthesized source IP and message punctuation.
