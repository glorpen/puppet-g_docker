class g_docker::daemon {

  assert_private()

  $_labels = $g_docker::labels.map | $k, $v| {
    $_v = $v?{
      Boolean => bool2str($v),
      default => $v
    }
    "${k}=${v}"
  }

  file { '/etc/docker/daemon.json':
    ensure  => 'present',
    content => to_json_pretty({
      'labels'              => $_labels,
      'insecure-registries' => $g_docker::insecure_registries
    }),
    require => Class['docker'],
    notify  => Exec['g_docker::daemon reload docker config']
  }

  exec {'g_docker::daemon reload docker config':
    command     => "pkill -HUP ${::docker::docker_ce_start_command}",
    refreshonly => true,
    require     => Service['docker'],
    path        => ['/bin', '/usr/bin']
  }
}
