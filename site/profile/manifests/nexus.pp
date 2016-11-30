#
# Sets up the nexus instance
#
class profile::nexus (

  $nexus_root       = '/srv',
  $nexus_nodes      = '', # A string f.e. '[ "10.0.2.12", "10.0.2.23" ]'
  $nexus_nodes_port = '8081',
  $storage_device   = undef,
) {

  require ::profile::java
  require ::profile::common::packages

  include ::nginx
  include ::profile::common::concat
  # $nexus_root configured in hiera for monitoring
  # FIXME rework cloudwatch to add defines and so manage easily each mount in each profiles
  include ::profile::common::cloudwatch
  include ::profile::common::cloudwatchlogs

  profile::register_profile { 'nexus': }

  if $::osfamily == 'RedHat'{
    selinux::boolean { 'httpd_can_network_connect':
      ensure => 'on',
    }
    selinux::boolean { 'httpd_setrlimit':
      ensure => 'on',
    }

    selinux::module { 'nginx':
      content => '
module nginx 1.0;

require {
        type httpd_t;
        type transproxy_port_t;
        class tcp_socket name_connect;
}

allow httpd_t transproxy_port_t:tcp_socket name_connect;
'
    }
  }

  if $nexus_nodes_port {
    $_nexus_nodes_port = $nexus_nodes_port
  } else {
    $_nexus_nodes_port = '8081'
  }

  if $storage_device {
    filesystem { $storage_device:
      ensure  => present,
      fs_type => 'xfs',
      options => '-f',
      before  => Class['::nexus']
    }

    #creates parent path if absent
    exec { "mkdir-${nexus_root}":
      command => "mkdir -p ${nexus_root}",
      creates => $nexus_root,
      path    => '/bin:/usr/bin',
      before  => Class['::nexus']
    }

    #configure the disk before mounting
    exec { "fix-readahead-${storage_device}":
      command => "/sbin/blockdev --setra 32 ${storage_device}",
      unless  => "/sbin/blockdev --getra ${storage_device} | grep -w 32",
      require => Filesystem[$storage_device],
    }

    #mount the storage volume, rights will be put by nexus class
    mount { $nexus_root:
      ensure  => 'mounted',
      device  => $storage_device,
      fstype  => 'xfs',
      options => 'noatime,nodiratime',
      atboot  => true,
      require => [ Filesystem[$storage_device],
                    Exec["mkdir-${nexus_root}"],
                    Exec["fix-readahead-${storage_device}"] ],
      before  => Class['::nexus']
    }
  }


  class { '::nexus':
    version    => '2.8.0',
    revision   => '05',
    nexus_root => $nexus_root, # All directories and files will be relative to this
    nexus_port => $_nexus_nodes_port,
  }
  contain ::nexus

  # [ "10.0.2.12:8081", "10.0.2.23:8081" ]
  $_nexus_nodes = suffix(
    unique(
      concat(
        [$::ipaddress],
        split(regsubst($nexus_nodes, '[\s\[\]\"]', '', 'G'), ',')
      )
    ),
    ":${_nexus_nodes_port}"
  )

  class { 'profile::nexus::nginx':
    nexus_nodes => $_nexus_nodes,
  }

}
