class g_docker::storage::overlay2_helper{

  include ::g_docker::storage::overlay2

  $ensure = $::g_docker::storage::overlay2::ensure
  $vg_name = pick($::g_docker::storage::overlay2::vg_name, $::g_docker::data_vg_name)
  $lv_name = $::g_docker::storage::overlay2::lv_name
  $size = $::g_docker::storage::overlay2::size

  if ($::g_docker::storage::overlay2::raid_level == undef) {
    $vol_resource = G_server::Volumes::Vol[$lv_name]
  } else {
    $vol_resource = G_server::Volumes::Raid[$lv_name]
  }

  if $ensure == 'present' {
    $vol_resource -> Class['docker']
  } else {
    Class['docker'] -> $vol_resource
  }

  $vol_options = {
    ensure     => $ensure,
    vg_name    => $vg_name,
    size       => $size,
    fs         => 'xfs',
    fs_options => '-n ftype=1',
    mountpoint => $::g_docker::docker_data_path
  }

  if ($::g_docker::storage::overlay2::raid_level == undef) {
    g_server::volumes::vol { $lv_name:
      * => $vol_options
    }
  } else {
    g_server::volumes::raid { $lv_name:
      level   => $::g_docker::storage::overlay2::raid_level,
      stripes => $::g_docker::storage::overlay2::raid_stripes,
      mirrors => $::g_docker::storage::overlay2::raid_mirrors,
      *       => $vol_options,
    }
  }
}
