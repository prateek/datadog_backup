# frozen_string_literal: true

require 'open3'
require 'timeout'
require 'fileutils'

describe 'bin/datadog_backup' do # rubocop:disable RSpec/DescribeClass
  # Contract Or[nil,String] => self
  def run_bin(env = {}, args = '')
    status = nil
    output = ''
    cmd = "bin/datadog_backup #{args}"
    Open3.popen2e(env, cmd) do |_i, oe, t|
      pid = t.pid

      Timeout.timeout(4.0) do
        oe.each do |v|
          output += v
        end
      end
    rescue Timeout::Error
      LOGGER.error "Timing out #{t.inspect} after 4 second"
      Process.kill(15, pid)
    ensure
      status = t.value
    end
    [output, status]
  end

  required_vars = %w[
    DD_API_KEY
    DD_APP_KEY
  ]

  env = {}
  required_vars.each do |v|
    env[v] = v.downcase
  end

  required_vars.map do |v|
    it "dies unless given ENV[#{v}]" do
      myenv = env.dup.tap { |h| h.delete(v) }
      _, status = run_bin(myenv, 'backup')
      expect(status).not_to be_success
    end
  end

  describe 'help' do
    subject(:bin) { run_bin(env, '--help') }

    it 'prints usage' do
      out_err, _status = bin
      expect(out_err).to match(/Usage: DD_API_KEY=/)
    end

    it 'exits cleanly' do
      _out_err, status = bin
      expect(status).to be_success
    end
  end

  describe '--*-only flags' do
    let(:site_url) { 'http://127.0.0.1:1' } # fail fast without real network
    let(:base_env) do
      {
        'DD_API_KEY' => 'dd_api_key',
        'DD_APP_KEY' => 'dd_app_key',
        'DD_SITE_URL' => site_url
      }
    end

    def with_temp_backup
      Dir.mktmpdir do |tmpdir|
        backup_root = File.join(tmpdir, 'backup')
        %w[dashboards monitors slos synthetics notebooks].each do |dir|
          FileUtils.mkdir_p(File.join(backup_root, dir))
          File.write(File.join(backup_root, dir, 'keep.txt'), 'x')
        end
        yield(tmpdir, backup_root)
      end
    end

    resource_flags = {
      'dashboards' => '--dashboards-only',
      'monitors' => '--monitors-only',
      'slos' => '--slos-only',
      'synthetics' => '--synthetics-only',
      'notebooks' => '--notebooks-only'
    }

    resource_flags.each do |resource, flag|
      it "purges only #{resource} when using #{flag}" do
        with_temp_backup do |tmpdir, backup_root|
          env = base_env.merge('PWD' => tmpdir)

          # Run backup which will purge first, then attempt network and fail fast.
          _out_err, _status = run_bin(env, "#{flag} backup")

          resource_dir = File.join(backup_root, resource)
          other_dirs = Dir.glob(File.join(backup_root, '*')).reject { |d| d == resource_dir }

          # Selected resource directory should have been purged (no files left)
          expect(Dir.glob(File.join(resource_dir, '*'))).to be_empty

          # Other resource directories should remain untouched (keep.txt still present)
          other_dirs.each do |dir|
            expect(Dir.glob(File.join(dir, '*'))).not_to be_empty
          end
        end
      end
    end
  end
end
