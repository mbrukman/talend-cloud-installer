#
# Sets up the mongodb instance
#
class profile::mongodb(

  $mongodb_nodes       = '', # A string f.e. '[ "10.0.2.12", "10.0.2.23" ]'
  $shared_key          = undef,
  $replset_auth_enable = false,
  $dbpath              = '/var/lib/mongo',
  $storage_device      = undef
) {

  require ::profile::common::packages

  include ::profile::common::concat
  # $dbpath configured in hiera for monitoring
  # FIXME rework cloudwatch to add defines and so manage easily each mount in each profiles
  include ::profile::common::cloudwatch

  profile::register_profile { 'mongodb': }

  # A list of strings, like ['10.0.2.12:27017', '10.0.2.23:27017']
  $_mongo_nodes = suffix(split(regsubst($mongodb_nodes, '[\s\[\]\"]', '', 'G'), ','), ':27017')

  # explicitly only support replica sets of size 3
  if size($_mongo_nodes) == 3 {
    $replset_name = 'tipaas'

    $replset_config = {
      'tipaas' => {
        ensure  => 'present',
        members => $_mongo_nodes
      }
    }

    if $replset_auth_enable == true {
      $mongo_auth = true
      $keyfile = '/var/lib/mongo/shared_key'
    } else {
      $mongo_auth = false
      $keyfile = undef
    }
  } else {
    $mongo_replset_name = undef
    $replset_name = undef
    $mongo_auth = true
  }

  if $storage_device {
    # File[$dbpath] is managed by mongodb::server::config.pp (called by mongodb::server)
    filesystem { $storage_device:
      ensure  => present,
      fs_type => 'xfs',
      options => '-f',
      before  => Class['::mongodb::server']
    }

    #creates parent path if absent
    exec { "mkdir-${dbpath}":
      command => "mkdir -p ${dbpath}",
      creates => $dbpath,
      path    => '/bin:/usr/bin',
      before  => Class['::mongodb::server']
    }

    #configure the disk before mounting
    exec { "fix-readahead-${storage_device}":
      command => "/sbin/blockdev --setra 32 ${storage_device}",
      unless  => "/sbin/blockdev --getra ${storage_device} | grep -w 32",
      require => Filesystem[$storage_device],
    }

    #mount the storage volume, rights will be put by File[$dbpath]
    mount { $dbpath:
      ensure  => 'mounted',
      device  => $storage_device,
      fstype  => 'xfs',
      options => 'noatime,nodiratime,noexec',
      atboot  => true,
      require => [ Filesystem[$storage_device],
                    Exec["mkdir-${dbpath}"],
                    Exec["fix-readahead-${storage_device}"] ],
      before  => Class['::mongodb::server']
    }
  }

  $create_admin_user = "/usr/bin/mongo ipaas --eval \"db.createUser({ \
    user: 'admin', \
    pwd: '${::master_password}', \
    roles: [ \
      {role: 'userAdminAnyDatabase', db: 'admin'}, \
      {role: 'dbAdminAnyDatabase', db: 'admin'}, \
      {role: 'readWriteAnyDatabase', db: 'admin'}, \
      {role: 'dbOwner', db: 'ipaas'} \
    ] \
});\" && /bin/touch /var/lock/mongo_admin_user_lock"

  class {'::mongodb::globals':
    manage_package_repo => true,
  }->
  class { '::mongodb::server':
    verbose        => true,
    auth           => $mongo_auth,
    bind_ip        => [$::ipaddress, '127.0.0.1'],
    replset        => $replset_name,
    replset_config => $replset_config,
    key            => $shared_key,
    keyfile        => $keyfile,
    dbpath         => $dbpath
  } ->
  class { '::mongodb::client':
  }

  $instanceLogicalId = pick($::cfn_resource_name, $::ec2_userdata, '')
  if $instanceLogicalId =~ /InstanceA/ {
    exec { 'setup MongoDB admin user':
      command => $create_admin_user,
      creates => '/var/lock/mongo_admin_user_lock',
      require => Class['::mongodb::client']
    }
  }

  contain ::mongodb::server
  contain ::mongodb::client

}
