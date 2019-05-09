define g_docker::runtime_config::config (
  String $container,
  String $group,
  String $filename,
  Optional[String] $source = undef,
  Optional[String] $content = undef,
  Boolean $reload = false
){
  include g_docker

  $sanitised_name = ::docker::sanitised_name($container)
  $container_config_path = "${::g_docker::runtime_config_path}/${sanitised_name}"
  $config_file = "${container_config_path}/${group}/${filename}"

  file { $config_file:
    ensure  => 'present',
    source  => $source,
    content => $content
  }

  if ($reload) {
    File[$config_file]
    ~>Exec["g_docker runtime config ${container}"]
  } else {
    File[$config_file]
    ~>Docker::Run[$container]
  }
}
