# db/seeds/sensors.rb
#
# Seeds sensor configurations for macOS and Linux.
# Safe to run at any time — uses find_or_create_by! with a block so attributes
# are only set on new records; existing sensor configs (including enabled state
# and read_position) are never touched.
#
# Run standalone with:
#   bin/rails runner "load Rails.root.join('db/seeds/sensors.rb')"

macos_sensors = [
  {
    name: "System Log",
    source_type: "syslog",
    log_path: "/var/log/system.log",
    description: "macOS system events and messages",
    parser_options: { "format" => "syslog" }
  },
  {
    name: "Install Log",
    source_type: "syslog",
    log_path: "/var/log/install.log",
    description: "Software installation events",
    parser_options: { "format" => "syslog" }
  },
  {
    name: "Unified Log Export",
    source_type: "syslog",
    log_path: "/tmp/unified_log_export.log",
    description: "Exported from: log show --predicate 'process == \"sshd\"' --last 1h",
    parser_options: { "format" => "line" }
  },
  {
    name: "Santa (if installed)",
    source_type: "endpoint",
    log_path: "/var/db/santa/santa.log",
    description: "Google Santa binary authorization logs",
    parser_options: { "format" => "json" }
  },
  {
    name: "OpenBSM Audit",
    source_type: "audit",
    log_path: "/var/audit/current",
    description: "macOS audit trail (requires root)",
    parser_options: { "format" => "bsm" }
  },
  {
    name: "Application Firewall",
    source_type: "firewall",
    log_path: "/var/log/appfirewall.log",
    description: "macOS Application Firewall events",
    parser_options: { "format" => "syslog" }
  }
]

macos_sensors.each do |sensor|
  SensorConfiguration.find_or_create_by!(domain: "cybersecurity", platform: "macos", name: sensor[:name]) do |s|
    s.source_type    = sensor[:source_type]
    s.log_path       = sensor[:log_path]
    s.description    = sensor[:description]
    s.parser_options = sensor[:parser_options]
    s.enabled        = false
  end
end

linux_sensors = [
  {
    name: "Auth Log (Debian/Ubuntu)",
    source_type: "syslog",
    log_path: "/var/log/auth.log",
    description: "Authentication events including SSH, sudo, PAM",
    parser_options: { "format" => "syslog" }
  },
  {
    name: "Secure Log (RHEL/CentOS)",
    source_type: "syslog",
    log_path: "/var/log/secure",
    description: "Authentication events on RHEL-based systems",
    parser_options: { "format" => "syslog" }
  },
  {
    name: "Syslog",
    source_type: "syslog",
    log_path: "/var/log/syslog",
    description: "General system messages",
    parser_options: { "format" => "syslog" }
  },
  {
    name: "Messages",
    source_type: "syslog",
    log_path: "/var/log/messages",
    description: "System messages (RHEL-based)",
    parser_options: { "format" => "syslog" }
  },
  {
    name: "Kernel Log",
    source_type: "kernel",
    log_path: "/var/log/kern.log",
    description: "Kernel messages including iptables, hardware events",
    parser_options: { "format" => "syslog" }
  },
  {
    name: "Apache Access Log",
    source_type: "webserver",
    log_path: "/var/log/apache2/access.log",
    description: "Apache HTTP server access log",
    parser_options: { "format" => "combined" }
  },
  {
    name: "Apache Error Log",
    source_type: "webserver",
    log_path: "/var/log/apache2/error.log",
    description: "Apache HTTP server error log",
    parser_options: { "format" => "line" }
  },
  {
    name: "Nginx Access Log",
    source_type: "webserver",
    log_path: "/var/log/nginx/access.log",
    description: "Nginx HTTP server access log",
    parser_options: { "format" => "combined" }
  },
  {
    name: "Nginx Error Log",
    source_type: "webserver",
    log_path: "/var/log/nginx/error.log",
    description: "Nginx HTTP server error log",
    parser_options: { "format" => "line" }
  },
  {
    name: "Fail2ban Log",
    source_type: "ids",
    log_path: "/var/log/fail2ban.log",
    description: "Fail2ban intrusion prevention events",
    parser_options: { "format" => "line" }
  },
  {
    name: "UFW Log",
    source_type: "firewall",
    log_path: "/var/log/ufw.log",
    description: "Uncomplicated Firewall events",
    parser_options: { "format" => "syslog" }
  },
  {
    name: "Audit Log",
    source_type: "audit",
    log_path: "/var/log/audit/audit.log",
    description: "Linux Audit Framework events",
    parser_options: { "format" => "audit" }
  },
  {
    name: "Journald Export",
    source_type: "syslog",
    log_path: "/tmp/journald_export.log",
    description: "Exported from: journalctl -u sshd --since '1 hour ago'",
    parser_options: { "format" => "line" }
  },
  {
    name: "Zeek Connection Log",
    source_type: "netflow",
    log_path: "/opt/zeek/logs/current/conn.log",
    description: "Zeek/Bro network connection logs",
    parser_options: { "format" => "zeek" }
  },
  {
    name: "Suricata EVE JSON",
    source_type: "ids",
    log_path: "/var/log/suricata/eve.json",
    description: "Suricata IDS events in EVE JSON format",
    parser_options: { "format" => "json" }
  }
]

linux_sensors.each do |sensor|
  SensorConfiguration.find_or_create_by!(domain: "cybersecurity", platform: "linux", name: sensor[:name]) do |s|
    s.source_type    = sensor[:source_type]
    s.log_path       = sensor[:log_path]
    s.description    = sensor[:description]
    s.parser_options = sensor[:parser_options]
    s.enabled        = false
  end
end

puts "macOS sensors: #{SensorConfiguration.where(platform: 'macos').count}"
puts "Linux sensors: #{SensorConfiguration.where(platform: 'linux').count}"
