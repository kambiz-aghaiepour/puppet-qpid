# Class: qpid::server
#
# This module manages the installation and config of the qpid server.
class qpid::server(
  $config_file = '/etc/qpidd.conf',
  $package_name = 'qpid-cpp-server',
  $package_ensure = present,
  $service_name = 'qpidd',
  $service_ensure = running,
  $service_enable = true,
  $port = '5672',
  $max_connections = '500',
  $worker_threads = '17',
  $connection_backlog = '10',
  $auth = 'no',
  $realm = 'QPID',
  $log_to_file = 'UNSET',
  $clustered = false,
  $cluster_name = 'test_cluster',
  $cluster_mechanism = 'ANONYMOUS',
  $cluster_bindnetaddr = '192.168.1.0',
  $cluster_mcastaddr = '226.94.1.1',
  $cluster_mcastport = '5405',
  $ssl = false,
  $ssl_package_name = 'qpid-cpp-server-ssl',
  $ssl_package_ensure = present,
  $ssl_port = '5671',
  $ssl_ca = '/etc/ipa/ca.crt',
  $ssl_cert = undef,
  $ssl_key = undef,
  $ssl_database_password = undef,
  $freeipa = false
) {

  validate_re($port, '\d+')
  validate_re($ssl_port, '\d+')
  validate_re($max_connections, '\d+')
  validate_re($worker_threads, '\d+')
  validate_re($connection_backlog, '\d+')
  validate_re($auth, '^(yes$|no$)')

  package { $package_name:
    ensure => $package_ensure
  }

  if $clustered == true {
    case $::operatingsystem {
      fedora: {
        $mechanism_option = 'ha-mechanism'
        package { "qpid-cpp-server-ha":
          ensure => installed,
        }
      }
      default: {
        $mechanism_option = 'cluster-mechanism'
        package { "qpid-cpp-server-cluster":
          ensure => installed,
        }
      }
    }
    class { "corosync":
      enable_secauth    => false,
      bind_address      => $cluster_bindnetaddr,
      multicast_address => $cluster_mcastaddr,
      port              => $cluster_mcastport
    }
    firewall { '001 qpid-corosync udp':
        proto    => 'udp',
        dport    => ['5405', '50007'],
        action   => 'accept',
    }
    firewall { '002 qpid-corosync tcp':
        proto    => 'tcp',
        dport    => ['5405', '8084', '11111', '14567', '16851', '21064', '50006', '50008', '50009'],
        action   => 'accept',
    }
  }

  file { $config_file:
    ensure  => present,
    owner   => 'root',
    group   => 'root',
    mode    => 644,
    content => template('qpid/qpidd.conf.erb'),
    subscribe => Package[$package_name]
  }

  if $ssl == true {
    if $ssl_database_password == undef {
      fail('ssl_database_passowrd must be set')
    }
    package { $ssl_package_name:
      ensure => $ssl_package_ensure,
      before => Nssdb::Create['qpidd'],
    }
    nssdb::create {"qpidd":
      owner_id => 'qpidd',
      group_id => 'qpidd',
      password => $ssl_database_password,
      cacert => $ssl_ca,
    }

    Nssdb::Create['qpidd'] ~> Service['qpidd']

    if $freeipa == true {
      certmonger::request_ipa_cert {"qpidd":
        seclib => "nss",
        nickname => "broker",
        principal => "qpid/${fqdn}",
      }
    } elsif $ssl_cert != undef and $ssl_key != undef {
      nssdb::add_cert_and_key{"qpidd":
        nickname=> 'broker',
        cert => $ssl_cert,
        key  => $ssl_key,
      }
    } else {
      fail('Missing cert or key')
    }
  }

  if $log_to_file != 'UNSET' {
    file { $log_to_file:
      ensure  => present,
      owner => 'qpidd',
      group => 'qpidd',
      mode => 644,
      notify => Service[$service_name]
    }
  }

  service { $service_name:
    ensure => $service_ensure,
    enable => $service_enable,
    subscribe => [Package[$package_name], File[$config_file]]
  }

}
