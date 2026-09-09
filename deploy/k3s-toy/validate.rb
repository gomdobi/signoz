# frozen_string_literal: true

require 'yaml'
require 'json'
require 'open3'
require 'digest'

# Local, read-only contract checks. No kubectl apply, API access or server writes.
module ToyValidation
  class Invalid < StandardError; end

  def self.documents(text)
    Psych.parse_stream(text).children.map do |document|
      stream = Psych::Nodes::Stream.new
      stream.children << document
      # macOS Psych 3 parses the official IPv6 scalar ::/0 as a Ruby Symbol.
      # Permit only this harmless scalar class; never instantiate arbitrary types.
      YAML.safe_load(stream.to_yaml, permitted_classes: [Symbol], aliases: false)
    end.compact
  end

  def self.require_true(condition, message)
    raise Invalid, message unless condition
  end

  def self.one(objects, kind, name)
    matches = objects.select { |o| o['kind'] == kind && o.dig('metadata', 'name') == name }
    require_true(matches.length == 1, "Expected one #{kind}/#{name}")
    matches.first
  end

  def self.pod_specs(object)
    case object['kind']
    when 'Deployment', 'StatefulSet', 'Job'
      [object.dig('spec', 'template', 'spec')]
    when 'ClickHouseInstallation', 'ClickHouseKeeperInstallation'
      object.dig('spec', 'templates', 'podTemplates').to_a.map { |p| p['spec'] }
    else
      []
    end.compact
  end

  def self.check(objects, casting)
    spec = casting.fetch('spec')
    require_true(spec.fetch('deployment') == { 'flavor' => 'kustomize', 'mode' => 'kubernetes' }, 'Not the official Kustomize target')
    require_true(casting.dig('metadata', 'name') == 'signoz', 'Unexpected experiment name')
    require_true((spec.keys - %w[deployment signoz ingester telemetrystore]).empty?, 'Unexpected customization: review before extending the official baseline')
    %w[signoz ingester telemetrystore].each do |component|
      require_true(spec[component].keys == ['spec'], 'Unexpected component customization')
      require_true(spec[component]['spec'].keys.sort == %w[image version], 'Only release image/version overrides are expected')
    end
    identities = objects.map { |o| [o['apiVersion'], o['kind'], o.dig('metadata', 'namespace'), o.dig('metadata', 'name')] }
    require_true(identities.uniq.length == identities.length, 'Duplicate Kubernetes resource identity')
    require_true(objects.none? { |o| %w[NetworkPolicy ValidatingAdmissionPolicy MutatingWebhookConfiguration].include?(o['kind']) }, 'Unexpected added security policy')
    require_true(objects.none? { |o| o.dig('metadata', 'labels', 'app.kubernetes.io/component') == 'mcp' }, 'MCP must remain disabled in this baseline')
    require_true(objects.all? { |o| [nil, 'signoz'].include?(o.dig('metadata', 'namespace')) }, 'Unexpected target namespace')
    one(objects, 'Namespace', 'signoz')
    one(objects, 'StatefulSet', 'signoz-metastore')
    one(objects, 'ClickHouseKeeperInstallation', 'signoz-clickhouse-keeper')
    signoz = one(objects, 'StatefulSet', 'signoz-signoz')
    ingester = one(objects, 'Deployment', 'signoz-ingester')
    clickhouse = one(objects, 'ClickHouseInstallation', 'signoz-clickhouse')
    { 'signoz' => signoz, 'ingester' => ingester, 'telemetrystore' => clickhouse }.each do |component, object|
      require_true(pod_specs(object).first.fetch('containers').first['image'] == spec[component]['spec']['image'], "#{component} image differs from casting")
    end

    migrator = pod_specs(one(objects, 'Job', 'signoz-telemetrystore-migrator')).first
    phases = migrator.fetch('initContainers') + migrator.fetch('containers')
    expected = [%w[migrate ready], %w[migrate bootstrap], %w[migrate sync up], %w[migrate async up]]
    require_true(phases.map { |c| c['args'] } == expected, 'Official migration sequence changed')
    require_true(phases.all? { |c| c['image'] == spec['ingester']['spec']['image'] }, 'Migrator/Collector image mismatch')

    containers = objects.flat_map { |o| pod_specs(o) }.flat_map { |p| p.fetch('initContainers', []) + p.fetch('containers', []) }
    containers.each do |container|
      env = container.fetch('env', [])
      require_true(env.map { |e| e['name'] }.uniq.length == env.length, 'Duplicate environment name in a container')
      require_true(env.all? { |e| !e.key?('value') || e['value'].is_a?(String) }, 'Non-string Kubernetes environment value')
    end
    images = containers.map { |c| c.fetch('image') }.uniq.sort
    require_true(images.none? { |i| i.end_with?(':latest') }, 'Active latest image found')
    {
      'objects' => objects.length,
      'kinds' => objects.group_by { |o| o['kind'] }.transform_values(&:length),
      'images' => images,
      'migration_phases' => phases.map { |c| c['name'] },
      'check_scope' => 'local generation and manifest contracts only; no cluster validation'
    }
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    root = File.expand_path(__dir__)
    casting = ToyValidation.documents(File.read(File.join(root, 'casting.yaml'))).fetch(0)
    docker_casting = ToyValidation.documents(File.read(File.join(root, '../foundry/casting.yaml'))).fetch(0)
    %w[signoz ingester telemetrystore].each do |component|
      %w[image version].each do |key|
        ToyValidation.require_true(casting.dig('spec', component, 'spec', key) == docker_casting.dig('spec', component, 'spec', key), "#{component} #{key} differs from the existing release baseline")
      end
    end
    output, _error, status = Open3.capture3(ARGV.fetch(0, 'kubectl'), 'kustomize', File.join(root, 'pours/deployment'))
    ToyValidation.require_true(status.success?, 'kubectl kustomize failed; raw output withheld')
    report = ToyValidation.check(ToyValidation.documents(output), casting)
    report['rendered_sha256'] = Digest::SHA256.hexdigest(output)
    puts JSON.pretty_generate(report)
  rescue StandardError => error
    # Never print generated manifests, environment values, or parser excerpts.
    message = error.is_a?(ToyValidation::Invalid) ? error.message : 'Parsing/tool failure; raw details withheld'
    warn "Validation failed: #{message}"
    exit 1
  end
end
