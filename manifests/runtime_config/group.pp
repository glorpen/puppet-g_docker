define g_docker::runtime_config::group(
  String $container,
  String $group_name = $name,
  Hash[String, Hash] $configs = {},
  Optional[String] $source = undef,
  Variant[String, Integer, Undef] $user = undef,
  Variant[String, Integer, Undef] $group = undef,
  Optional[String] $mode = undef,
  Boolean $source_reload = false
){

  assert_private()

  $sanitised_name = ::docker::sanitised_name($container)
  $container_path = "${::g_docker::runtime_config_path}/${sanitised_name}"
  $group_path = "${container_path}/${group_name}"

  if $source {
    $_opts = {
      recurse => 'remote',
    }
  } else {
    $_opts = {
      recurse => true,
      recurselimit => 1,
    }
  }

  file { $group_path:
    ensure => directory,
    source => $source,
    backup => false,
    force  => true,
    purge  => true,
    owner  => $user,
    group  => $group,
    mode   => $mode,
    *      => $_opts
  }

  if $source {
    if $source_reload {
      File[$group_path]
      ~>Exec["g_docker runtime config ${container}"]
    } else {
      File[$group_path]
      ~>G_docker::Compat::Run[$container]
    }
  } else {
    $configs.each |$config_name, $config| {
      g_docker::runtime_config::config { "${container}:${group_name}:${config_name}":
        require      => [Class['docker'], File[$group_path]],
        container    => $container,
        config_group => $group_name,
        filename     => $config_name,
        *            => $config
      }
    }
  }
}
