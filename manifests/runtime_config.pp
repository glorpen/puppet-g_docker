# @summary This type setups configuration dir for container and Exec chain for hot reloading.
#
# @param ensure
#   Creates or removes config directory (present|absent).
# @param reload_signal
#   Signal to send to container when reloading was requested.
#
define g_docker::runtime_config(
  Enum['present', 'absent'] $ensure = 'present',
  Optional[String] $reload_signal = undef
){
  assert_private()

  $sanitised_name = ::docker::sanitised_name($name)
  $container_path = "${::g_docker::runtime_config_path}/${sanitised_name}"

  $lock_file = "${container_path}/.no-reload"
  $reload_name = "g_docker runtime config ${name}"
  $semaphore_name = "g_docker runtime config semaphore for ${name}"
  $cleanup_name = "g_docker runtime config cleanup ${name}"

  $_ensure_directory = $ensure?{
    'present' => 'directory',
    default   => 'absent'
  }
  file { $container_path:
    ensure       => $_ensure_directory,
    recurse      => true,
    backup       => false,
    force        => true,
    purge        => true,
    recurselimit => 1
  }

  if $ensure == 'present' and $reload_signal {
    exec { $semaphore_name:
      require     => File[$container_path],
      subscribe   => Service["${::g_docker::service_prefix}${sanitised_name}"],
      refreshonly => true,
      path        => '/bin:/usr/bin',
      command     => "touch ${lock_file}"
    }

    # do not trigger reload if service is restarting
    exec { $reload_name:
      refreshonly => true,
      path        => '/bin:/usr/bin',
      command     => "docker kill -s ${reload_signal} ${sanitised_name}",
      #TODO: no error checking when SIGHUP reload, but no error checking on container start as it is detached..
      require     => [Exec[$semaphore_name], G_docker::Compat::Run[$name]],
      tries       => 3,
      unless      => "test -f ${lock_file}"
    }

    exec { $cleanup_name:
      subscribe   => Exec[$semaphore_name],
      require     => Exec[$reload_name],
      path        => '/bin:/usr/bin',
      command     => "rm ${lock_file}",
      refreshonly => true
    }
  }
}
