require 'spec_helper'

describe 'G_docker::Run' do
  let(:title) { 'test' }
  let(:params) do
    {
      'image' => 'example:test',
    }
  end
  let(:pre_condition) { 'class {"g_docker": data_vg_name => "vg_test", runtime_config_path => "/config.d" }' }

  context 'with defaults' do
    it { is_expected.to compile }
  end
  context 'with runtime config and hot reload' do
    let(:params) do
      super().merge(
        'runtime_configs' => {
          'group1' => {
            'target' => '/srv',
            'configs' => {
              'test.yaml' => {
                'content' => 'test-content',
                'reload' => true,
              },
            },
          },
        },
      )
    end

    it { is_expected.to compile }
    it 'wraps reload command' do
      is_expected.to contain_docker__run('test')
      semaphore_name = 'g_docker runtime config semaphore for test'
      reload_name = 'g_docker runtime config test'
      cleanup_name = 'g_docker runtime config cleanup test'

      is_expected.to contain_exec(reload_name).with_command('docker kill -s HUP test').that_requires("Exec[#{semaphore_name}]").that_notifies("Exec[#{cleanup_name}]")
      is_expected.to contain_file('/config.d/test/group1/test.yaml').that_notifies("Exec[#{reload_name}]")
    end
  end
end
