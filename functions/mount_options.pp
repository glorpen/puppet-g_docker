function g_docker::mount_options(
  Enum['bind','volume','tmpfs'] $type,
  String $source,
  String $destination,
  Optional[Boolean] $readonly = false,
  Optional[Enum['shared','slave','private','rshared','rslave','rprivate']] $propagation = 'rprivate'
) >> String {
  $_readonly = $_readonly?{
    true => ',readonly',
    default => ''
  }
  
  $_propagation = $propagation?{
    'rprivate' => '',
    default => ",bind-propagation=${propagation}"
  }
  
  "type=${type},source=${source},destination=${destination}${_readonly}${_propagation}"
}
