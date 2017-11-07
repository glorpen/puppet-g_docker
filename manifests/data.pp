define g_docker::data(
  Hash $volumes = {}
){
  include ::g_docker
  # TODO: add handling for ensure: absent, ensure: stopped
  
  file { "${::g_docker::data_path}/${name}":
    ensure => directory,
    backup => false,
    force => true,
    require => File[$::g_docker::data_path]
  }
  
  $volumes.each | $vol_name, $vol_config | {
    ::g_docker::data::volume { "${name}:${vol_name}":
      volume_name => $vol_name,
      data_name => $name,
      * => $vol_config
    }
  }
}
