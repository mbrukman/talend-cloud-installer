require 'spec_helper_acceptance'

on hosts_with_role(hosts, 'mongodb') do
  describe "profile::mongodb" do

    describe "mongodb" do

      it 'should provision mongodb database profile' do
        pp = <<-EOS
        class { 'profile::db::mongodb':
        }
        EOS

        # With the version of java that ships with pe on debian wheezy, update-alternatives
        # throws an error on the first run due to missing alternative for policytool. It still
        # updates the alternatives for java
        agent = only_host_with_role(hosts, 'mongodb')

        apply_manifest_on(agent, pp, :catch_failures => true, :modulepath => '/tmp/puppet/site:/tmp/puppet/modules', :hiera_config => '/tmp/puppet/hiera.yaml')

      end

      describe package('mongodb-server') do
        it { is_expected.to be_installed }
      end

      describe service('mongod') do
        it { is_expected.to be_enabled }
        it { is_expected.to be_running }
      end

      describe port(27017) do
        it { should be_listening }
      end


    end
  end
end