# frozen_string_literal: true

require 'minitest/autorun'
require_relative 'validate'

TOY_KUBECTL = ARGV.shift || 'kubectl'

class ToyValidationTest < Minitest::Test
  def setup
    @casting = ToyValidation.documents(File.read(File.join(__dir__, 'casting.yaml'))).first
    output, _error, status = Open3.capture3(TOY_KUBECTL, 'kustomize', File.join(__dir__, 'pours/deployment'))
    raise 'Generate the official baseline with make forge first' unless status.success?
    @objects = ToyValidation.documents(output)
  end

  def test_official_baseline
    report = ToyValidation.check(@objects, @casting)
    assert_operator report['objects'], :>, 0
    assert_equal %w[ready bootstrap sync async], report['migration_phases']
  end

  def test_mismatched_migrator_fails
    job = ToyValidation.one(@objects, 'Job', 'signoz-telemetrystore-migrator')
    job['spec']['template']['spec']['containers'][0]['image'] = 'invalid:version'
    assert_raises(ToyValidation::Invalid) { ToyValidation.check(@objects, @casting) }
  end

  def test_non_string_environment_fails
    pod = ToyValidation.one(@objects, 'StatefulSet', 'signoz-signoz')
    pod['spec']['template']['spec']['containers'][0]['env'][0]['value'] = true
    assert_raises(ToyValidation::Invalid) { ToyValidation.check(@objects, @casting) }
  end

  def test_added_policy_fails
    @objects << { 'kind' => 'NetworkPolicy', 'metadata' => { 'name' => 'unexpected' } }
    assert_raises(ToyValidation::Invalid) { ToyValidation.check(@objects, @casting) }
  end

  def test_arbitrary_yaml_object_is_rejected
    assert_raises(Psych::DisallowedClass) { ToyValidation.documents('--- !ruby/object:Object {}') }
  end

  def test_yaml_alias_is_rejected
    assert_raises(Psych::BadAlias) { ToyValidation.documents("---\na: &a hello\nb: *a\n") }
  end
end
