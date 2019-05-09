class g_docker::firewall::native_helper {
  if $::g_docker::installed_version != undef and $::g_docker::installed_version_symbol == 'ce' {
      $_isolation_single = $::g_docker::installed_version <= SemVer('18.3.0')
      $_isolation_stage = ! $_isolation_single
  } else {
    # not sure, so to be safe enable both
    $_isolation_single = true
    $_isolation_stage = true
  }

  if $_isolation_single {
    firewallchain { 'DOCKER-ISOLATION:filter:IPv4':
      ensure  => present,
      purge   => false,
      require => Class['docker']
    }
  }

  if $_isolation_stage {
    firewallchain { 'DOCKER-ISOLATION-STAGE-1:filter:IPv4':
      ensure  => present,
      purge   => false,
      require => Class['docker']
    }
    firewallchain { 'DOCKER-ISOLATION-STAGE-2:filter:IPv4':
      ensure  => present,
      purge   => false,
      require => Class['docker']
    }
  }
}
