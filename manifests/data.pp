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
  
  create_resources(::g_docker::data::volume, $volumes, {
    data_name => $name
  })
}
