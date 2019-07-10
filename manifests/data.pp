# @summary Creates persistent data volumes for container.
define g_docker::data(
  Enum['present','absent'] $ensure = 'present',
  Hash[String, Hash] $volumes = {}
){
  include ::g_docker

  $_data_ensure = $ensure?{
    'present' => directory,
    default   => $ensure
  }
  file { "${::g_docker::data_path}/${name}":
    ensure => $_data_ensure,
    backup => false,
    force  => true,
  }

  if $ensure == 'present' {
    File[$::g_docker::data_path]
    ->File["${::g_docker::data_path}/${name}"]
  } else {
    File["${::g_docker::data_path}/${name}"]
    ->File[$::g_docker::data_path]
  }

  $volumes.each | $vol_name, $vol_config | {
    ::g_docker::data::volume { "${name}:${vol_name}":
      ensure      => $ensure,
      volume_name => $vol_name,
      data_name   => $name,
      *           => $vol_config
    }
  }
}
