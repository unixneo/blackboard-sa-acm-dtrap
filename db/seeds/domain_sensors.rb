# db/seeds/domain_sensors.rb
#
# Creates domain-specific sensor records by copying from the cybersecurity baseline.
# Each domain gets its own copies so operators can edit paths/types independently.
#
# Safe to run at any time on any system:
#   - Uses find_or_create_by! keyed on (domain, platform, name)
#   - Existing records (including all cybersecurity sensors) are NEVER modified
#   - New records are created disabled; operator enables after reviewing/updating paths
#
# Run standalone with:
#   bin/rails runner "load Rails.root.join('db/seeds/domain_sensors.rb')"

# ── netops: mirror cybersecurity sensors ──────────────────────────────────────
# netops uses the same log infrastructure as cybersecurity; enabled state is
# kept in sync so operators see the same active sensors under both domains.

cybersecurity_sensors = SensorConfiguration.for_domain('cybersecurity').to_a

cybersecurity_sensors.each do |source|
  record = SensorConfiguration.find_or_initialize_by(
    domain:   'netops',
    platform: source.platform,
    name:     source.name
  )
  if record.new_record?
    record.source_type           = source.source_type
    record.log_path              = source.log_path
    record.description           = source.description
    record.parser_options        = source.parser_options.dup
    record.poll_interval_seconds = source.poll_interval_seconds
    record.enabled               = source.enabled
    record.save!
    puts "  Created: [netops/#{source.platform}] #{source.name} (enabled=#{source.enabled})"
  else
    record.update(enabled: source.enabled)
    puts "  Synced:  [netops/#{source.platform}] #{source.name} (enabled=#{source.enabled})"
  end
end

# ── medical: domain-specific log sources ──────────────────────────────────────
# Linux only — medical systems run on servers, not workstations.
# All created disabled; operators update paths to match their EHR/device vendor.

medical_sensors = [
  {
    name:        'EHR Audit Log',
    source_type: 'ehr_audit',
    log_path:    '/var/log/ehr/audit.log',
    description: 'EHR system audit trail — record access, create, modify, delete, sign events'
  },
  {
    name:        'Medical Device Alerts',
    source_type: 'medical_device',
    log_path:    '/var/log/devices/alerts.log',
    description: 'Clinical device alarm log — ventilators, infusion pumps, patient monitors'
  },
  {
    name:        'Pharmacy Dispensing Log',
    source_type: 'pharmacy',
    log_path:    '/var/log/pharmacy/dispense.log',
    description: 'Medication dispensing events from automated dispensing cabinet (e.g. Pyxis, Omnicell)'
  },
  {
    name:        'Lab Notifications',
    source_type: 'lab',
    log_path:    '/var/log/lab/results.log',
    description: 'Laboratory result delivery events from LIS'
  },
  {
    name:        'Physical Access Log',
    source_type: 'physical_access',
    log_path:    '/var/log/access/doors.log',
    description: 'Badge reader events for restricted areas — ICU, pharmacy, server room'
  },
]

medical_sensors.each do |attrs|
  record = SensorConfiguration.find_or_initialize_by(
    domain:   'medical',
    platform: 'linux',
    name:     attrs[:name]
  )
  if record.new_record?
    record.source_type           = attrs[:source_type]
    record.log_path              = attrs[:log_path]
    record.description           = attrs[:description]
    record.parser_options        = { 'format' => 'line' }
    record.poll_interval_seconds = 60
    record.enabled               = false
    record.save!
    puts "  Created: [medical/linux] #{attrs[:name]}"
  else
    puts "  Skipped: [medical/linux] #{attrs[:name]}"
  end
end

# ── financial: domain-specific log sources ────────────────────────────────────
# Linux only — payment and fraud systems run on servers.
# All created disabled; operators update paths to match their payment stack.

financial_sensors = [
  {
    name:        'Transaction Log',
    source_type: 'transaction',
    log_path:    '/var/log/payments/transactions.log',
    description: 'Payment transaction events — authorizations, declines, refunds, reversals'
  },
  {
    name:        'Authentication Log',
    source_type: 'auth',
    log_path:    '/var/log/auth/sessions.log',
    description: 'Login, MFA, and session events for customer and staff authentication'
  },
  {
    name:        'API Gateway Log',
    source_type: 'api_gateway',
    log_path:    '/var/log/api/access.log',
    description: 'API access log for payment and account management endpoints'
  },
  {
    name:        'Fraud Alert Log',
    source_type: 'fraud_system',
    log_path:    '/var/log/fraud/alerts.log',
    description: 'Alerts triggered by existing fraud rules and velocity checks'
  },
  {
    name:        'Database Audit Log',
    source_type: 'db_audit',
    log_path:    '/var/log/db/audit.log',
    description: 'Database query audit trail for sensitive tables — accounts, cards, transactions'
  },
]

financial_sensors.each do |attrs|
  record = SensorConfiguration.find_or_initialize_by(
    domain:   'financial',
    platform: 'linux',
    name:     attrs[:name]
  )
  if record.new_record?
    record.source_type           = attrs[:source_type]
    record.log_path              = attrs[:log_path]
    record.description           = attrs[:description]
    record.parser_options        = { 'format' => 'line' }
    record.poll_interval_seconds = 60
    record.enabled               = false
    record.save!
    puts "  Created: [financial/linux] #{attrs[:name]}"
  else
    puts "  Skipped: [financial/linux] #{attrs[:name]}"
  end
end

puts "\nAll domain sensor counts:"
KnowledgeSource::DOMAINS.each do |d|
  count = SensorConfiguration.for_domain(d).count
  puts "  #{d}: #{count}" if count > 0
end
