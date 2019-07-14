define g_docker::runtime_config::config (
  String $container,
  String $config_group,
  String $filename,
  Optional[String] $source = undef,
  Optional[String] $content = undef,
  Variant[String, Integer, Undef] $user = undef,
  Variant[String, Integer, Undef] $group = undef,
  Optional[String] $mode = undef,
  Boolean $reload = false
){
  include g_docker

  $sanitised_name = ::docker::sanitised_name($container)
  $container_config_path = "${::g_docker::runtime_config_path}/${sanitised_name}"
  $config_file = "${container_config_path}/${group}/${filename}"

  if $source {
    $_opts = {
      recurse => 'remote',
    }
  } else {
    $_opts = {
      recurse => true,
    }
  }

  file { $config_file:
    ensure  => 'present',
    source  => $source,
    content => $content,
    force   => true,
    backup  => false,
    owner   => $user,
    group   => $group,
    mode    => $mode,
    *       => $_opts
  }

  if ($reload) {
    File[$config_file]
    ~>Exec["g_docker runtime config ${container}"]
  } else {
    File[$config_file]
    ~>Docker::Run[$container]
  }
}
