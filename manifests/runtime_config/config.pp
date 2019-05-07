define g_docker::runtime_config::config (
  String $container,
  String $group,
  String $filename,
  Optional[String] $source = undef,
  Optional[String] $content = undef,
  Variant[Boolean, Enum['HUP','USR1', 'USR2']] $reload = false,
){
  include g_docker

  $sanitised_name = ::docker::sanitised_name($container)
  $container_config_path = "${::g_docker::runtime_config_path}/${sanitised_name}"
  $config_file = "${container_config_path}/${group}/${filename}"

  $signal = $reload?{
    true => 'HUP',
    String => $reload,
    default => undef
  }

  file { $config_file:
    ensure  => 'present',
    source  => $source,
    content => $content
  }

  if ($container and $signal) {
    $lock_file = "${container_config_path}/.no-reload"
    $reload_name = "g_docker runtime config ${container}"
    $semaphore_name = "g_docker runtime config semaphore for ${container}"

    ensure_resource('exec', $semaphore_name, {
      'require'     => File[$container_config_path],
      'subscribe'   => Service["${::g_docker::service_prefix}${sanitised_name}"],
      'refreshonly' => true,
      'path'        => '/bin:/usr/bin',
      'command'     => "touch ${lock_file}"
    })

    # do not trigger reload if service is restarting
    ensure_resource('exec', $reload_name, {
      'refreshonly' => true,
      'path'        => '/bin:/usr/bin',
      'command'     => "docker kill -s ${signal} ${sanitised_name}",
      'require'     => [Exec[$semaphore_name], Docker::Run[$container]],
      'tries'       => 3,
      'unless'      => "test -f ${lock_file}"
    })

    ensure_resource('exec', "g_docker runtime config cleanup ${container}", {
      'subscribe'   => Exec[$semaphore_name],
      'require'     => Exec[$reload_name],
      'path'        => '/bin:/usr/bin',
      'command'     => "rm ${lock_file}",
      'refreshonly' => true
    })

    File[$config_file]
    ~>Exec[$reload_name]
  }
}
